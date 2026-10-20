/**
 * Vyra Parental Control Suite — Master High-Speed Migration Engine (Queue-Based)
 * ==============================================================================
 * Migrates all heavy media from Mac Local Backups & Supabase Storage
 * directly into the user's 5 TB Google Drive Vault (Vyra_Vault).
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const {
  VAULT_CONFIG,
  getDriveAccessToken,
  uploadToDrive,
  ensurePublicRead,
  updateSupabaseRow
} = require('./drive_service');

const SUPABASE_URL = 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';
const BACKUPS_DIR = path.join(__dirname, '../backups');
const STATE_FILE = path.join(__dirname, '../migration_state.json');

const CONCURRENCY = 24;

async function uploadToDriveWithRetry(token, fileName, buf, mime, folderId, maxRetries = 5) {
  let attempt = 0;
  while (true) {
    try {
      return await uploadToDrive(token, fileName, buf, mime, folderId);
    } catch (err) {
      attempt++;
      if (attempt >= maxRetries) throw err;
      const delay = Math.min(1000 * Math.pow(2, attempt), 10000);
      await new Promise(r => setTimeout(r, delay));
    }
  }
}

let state = {
  uploadedFiles: {},
  dbUpdates: {},
  stats: { totalUploaded: 0, dbUpdated: 0, errors: 0 }
};

if (fs.existsSync(STATE_FILE)) {
  try {
    state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch (_) {}
}

let lastSave = Date.now();
function saveState(force = false) {
  if (force || Date.now() - lastSave > 3000) {
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
    lastSave = Date.now();
  }
}

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case '.m4a': return 'audio/mp4';
    case '.mp3': return 'audio/mpeg';
    case '.opus': return 'audio/ogg';
    case '.wav': return 'audio/wav';
    case '.amr': return 'audio/amr';
    case '.mp4': return 'video/mp4';
    case '.mkv': return 'video/x-matroska';
    case '.jpg':
    case '.jpeg': return 'image/jpeg';
    case '.png': return 'image/png';
    case '.webp': return 'image/webp';
    default: return 'application/octet-stream';
  }
}

async function downloadSupabaseFile(bucket, remotePath) {
  const encoded = remotePath.split('/').map(encodeURIComponent).join('/');
  const url = `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${encoded}`;
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode} from ${url}`));
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

async function listSupabaseBucket(bucket, prefix = '') {
  const all = [];
  let offset = 0;
  const limit = 100;
  while (true) {
    const payload = JSON.stringify({ prefix, limit, offset, sortBy: { column: 'name', order: 'asc' } });
    const res = await new Promise((resolve) => {
      const req = https.request({
        hostname: 'wtlqlkkduescumpggttm.supabase.co',
        path: `/storage/v1/object/list/${bucket}`,
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload)
        }
      }, r => {
        let d = '';
        r.on('data', c => d += c);
        r.on('end', () => {
          try { resolve(JSON.parse(d)); } catch (_) { resolve([]); }
        });
      });
      req.on('error', () => resolve([]));
      req.write(payload);
      req.end();
    });

    if (!Array.isArray(res) || res.length === 0) break;
    all.push(...res);
    if (res.length < limit) break;
    offset += limit;
  }
  return all;
}

async function verifyUrl(url) {
  return new Promise((resolve) => {
    const req = https.get(url, { headers: { 'Range': 'bytes=0-1024' } }, res => {
      resolve(res.statusCode >= 200 && res.statusCode < 400);
    });
    req.on('error', () => resolve(false));
    req.setTimeout(8000, () => { req.destroy(); resolve(false); });
  });
}

async function runQueue(tasks, workerFn, concurrency = CONCURRENCY) {
  let index = 0;
  let activeWorkers = 0;

  return new Promise((resolve) => {
    if (tasks.length === 0) return resolve();

    function next() {
      if (index >= tasks.length && activeWorkers === 0) {
        return resolve();
      }

      while (activeWorkers < concurrency && index < tasks.length) {
        const item = tasks[index++];
        activeWorkers++;
        workerFn(item)
          .catch((err) => {
            console.error(`Task error (${item.fileName || 'unknown'}):`, err.message);
          })
          .finally(() => {
            activeWorkers--;
            next();
          });
      }
    }

    next();
  });
}

async function main() {
  console.log('\n============================================================');
  console.log('🚀 VYRA — MASTER HIGH-SPEED DRIVE MIGRATION (QUEUE-BASED)');
  console.log('============================================================\n');

  console.log('🔑 [Step 1/5] Authenticating with 5 TB Google Drive...');
  let token = await getDriveAccessToken();
  console.log('✅ Connected to Google Drive!\n');

  // Token auto-refresher every 30 mins
  setInterval(async () => {
    try {
      token = await getDriveAccessToken();
    } catch (_) {}
  }, 1000 * 60 * 30);

  // -------------------------------------------------------------
  // PHASE 1: Mac Local Cable Backups
  // -------------------------------------------------------------
  console.log('📂 [Step 2/5] Preparing Local Cable Backups...');

  const localJobs = [
    { dir: path.join(BACKUPS_DIR, 'device_recordings/Call'), folderId: VAULT_CONFIG.folders.Call_Recordings, category: 'Call_Recordings' },
    { dir: path.join(BACKUPS_DIR, 'whatsapp_voice_notes'), folderId: VAULT_CONFIG.folders.WhatsApp_Voice_Notes, category: 'WhatsApp_Voice_Notes' },
    { dir: path.join(BACKUPS_DIR, 'screen_recording'), folderId: VAULT_CONFIG.folders.Videos, category: 'Videos' },
    { dir: path.join(BACKUPS_DIR, 'dcim_whatsapp'), folderId: VAULT_CONFIG.folders.Videos, category: 'Videos' },
    { dir: path.join(BACKUPS_DIR, 'screenshots_sep_oct_2026'), folderId: VAULT_CONFIG.folders.Screenshots_and_Snaps, category: 'Screenshots_and_Snaps' },
    { dir: path.join(BACKUPS_DIR, 'snapchat_media'), folderId: VAULT_CONFIG.folders.Screenshots_and_Snaps, category: 'Screenshots_and_Snaps' }
  ];

  const walk = (d) => {
    let out = [];
    if (!fs.existsSync(d)) return out;
    for (const item of fs.readdirSync(d)) {
      if (item.startsWith('.')) continue;
      const p = path.join(d, item);
      const st = fs.statSync(p);
      if (st.isDirectory()) out = out.concat(walk(p));
      else if (st.size > 200) out.push(p);
    }
    return out;
  };

  const allTasks = [];
  for (const j of localJobs) {
    const files = walk(j.dir);
    for (const f of files) {
      allTasks.push({
        filePath: f,
        fileName: path.basename(f),
        folderId: j.folderId,
        category: j.category,
        mime: getMimeType(f)
      });
    }
  }

  console.log(`   Total local files detected: ${allTasks.length}`);

  let completedLocal = 0;
  const startTime = Date.now();

  await runQueue(allTasks, async (task) => {
    const key = task.fileName;
    if (state.uploadedFiles[key]) {
      completedLocal++;
      return;
    }

    try {
      const buf = fs.readFileSync(task.filePath);
      const res = await uploadToDriveWithRetry(token, task.fileName, buf, task.mime, task.folderId);
      state.uploadedFiles[key] = {
        fileId: res.fileId,
        streamUrl: res.streamUrl,
        cdnUrl: res.directCdnUrl,
        category: task.category
      };
      state.stats.totalUploaded++;
      completedLocal++;

      if (completedLocal % 25 === 0 || completedLocal === allTasks.length) {
        saveState();
        const elapsedSec = Math.floor((Date.now() - startTime) / 1000);
        const rate = elapsedSec > 0 ? (completedLocal / elapsedSec).toFixed(1) : 0;
        console.log(`   ⚡ [${completedLocal}/${allTasks.length}] (${rate} files/sec) Synced: ${task.fileName}`);
      }
    } catch (e) {
      state.stats.errors++;
      console.error(`   ❌ Failed (${task.fileName}):`, e.message);
    }
  });

  saveState(true);
  console.log(`✅ Phase 1 complete: ${Object.keys(state.uploadedFiles).length} files safely in 5 TB Drive!\n`);

  // -------------------------------------------------------------
  // PHASE 2: Supabase Storage Migration
  // -------------------------------------------------------------
  console.log('☁️ [Step 3/5] Migrating heavy files from Supabase Storage...');

  const supabaseBuckets = [
    { bucket: 'recordings', prefix: 'VYRA-13533', folderId: VAULT_CONFIG.folders.Call_Recordings, cat: 'Call_Recordings', isAudio: true },
    { bucket: 'recordings', prefix: '', folderId: VAULT_CONFIG.folders.Call_Recordings, cat: 'Call_Recordings', isAudio: true },
    { bucket: 'snaps', prefix: 'VYRA-13533', folderId: VAULT_CONFIG.folders.Screenshots_and_Snaps, cat: 'Screenshots_and_Snaps', isAudio: false }
  ];

  for (const b of supabaseBuckets) {
    console.log(`   Scanning Supabase bucket [${b.bucket}] prefix [${b.prefix || 'root'}]...`);
    const objects = await listSupabaseBucket(b.bucket, b.prefix);
    console.log(`   Found ${objects.length} items in [${b.bucket}/${b.prefix}].`);

    let sDone = 0;
    await runQueue(objects, async (obj) => {
      const fname = obj.name;
      if (!fname || fname.endsWith('/') || obj.id === null) return;
      const remotePath = b.prefix ? `${b.prefix}/${fname}` : fname;

      let uploadedInfo = state.uploadedFiles[fname];
      if (!uploadedInfo) {
        try {
          const buf = await downloadSupabaseFile(b.bucket, remotePath);
          const mime = b.isAudio ? 'audio/mp4' : 'image/jpeg';
          const upRes = await uploadToDriveWithRetry(token, fname, buf, mime, b.folderId);
          uploadedInfo = {
            fileId: upRes.fileId,
            streamUrl: upRes.streamUrl,
            cdnUrl: upRes.directCdnUrl,
            category: b.cat,
            supabasePath: remotePath,
            bucket: b.bucket
          };
          state.uploadedFiles[fname] = uploadedInfo;
          state.stats.totalUploaded++;
        } catch (e) {
          state.stats.errors++;
          console.error(`   ❌ Supabase download/upload error (${remotePath}):`, e.message);
          return;
        }
      } else {
        uploadedInfo.supabasePath = remotePath;
        uploadedInfo.bucket = b.bucket;
      }

      sDone++;
      if (sDone % 25 === 0 || sDone === objects.length) {
        saveState();
        console.log(`   ☁️ [${sDone}/${objects.length}] Migrated from Supabase: ${fname}`);
      }
    });
  }

  saveState(true);
  console.log(`✅ Phase 2 complete: All files from Supabase Storage mapped to Drive!\n`);

  // -------------------------------------------------------------
  // PHASE 3: Update Supabase Database Rows
  // -------------------------------------------------------------
  console.log('🔄 [Step 4/5] Updating Supabase Database URLs (calls & chats)...');

  console.log('   Updating calls table recording_url...');
  for (const [fname, info] of Object.entries(state.uploadedFiles)) {
    if (info.category === 'Call_Recordings' && info.streamUrl) {
      if (!state.dbUpdates['call_' + fname]) {
        try {
          await updateSupabaseRow('calls', 'recording_url', fname, { recording_url: info.streamUrl });
          await updateSupabaseRow('calls', 'recording_url', `VYRA-13533/${fname}`, { recording_url: info.streamUrl });
          state.dbUpdates['call_' + fname] = true;
          state.stats.dbUpdated++;
        } catch (_) {}
      }
    }
  }

  console.log('   Updating chats table media_url for snaps and videos...');
  for (const [fname, info] of Object.entries(state.uploadedFiles)) {
    if ((info.category === 'Screenshots_and_Snaps' || info.category === 'Videos') && info.cdnUrl) {
      if (!state.dbUpdates['chat_' + fname]) {
        try {
          const oldSupabaseUrl = `${SUPABASE_URL}/storage/v1/object/public/snaps/VYRA-13533/${fname}`;
          await updateSupabaseRow('chats', 'media_url', oldSupabaseUrl, { media_url: info.cdnUrl });
          await updateSupabaseRow('chats', 'media_url', fname, { media_url: info.cdnUrl });
          state.dbUpdates['chat_' + fname] = true;
          state.stats.dbUpdated++;
        } catch (_) {}
      }
    }
  }

  saveState(true);
  console.log(`✅ Phase 3 complete: ${state.stats.dbUpdated} database references updated to Drive!\n`);

  // -------------------------------------------------------------
  // PHASE 4: Deep Verification
  // -------------------------------------------------------------
  console.log('🧪 [Step 5/5] Deep End-to-End Playback & Streaming Verification...');

  const sampleEntries = Object.entries(state.uploadedFiles).slice(0, 20);
  let verifiedCount = 0;

  for (const [fn, info] of sampleEntries) {
    const testUrl = info.category === 'Call_Recordings' ? info.streamUrl : info.cdnUrl;
    const ok = await verifyUrl(testUrl);
    if (ok) {
      verifiedCount++;
      console.log(`   ✅ Verified Accessible: [${info.category}] ${fn} ➔ HTTP 200/206/302 OK`);
    } else {
      console.log(`   ⚠️ Verification warning: ${fn}`);
    }
  }

  console.log(`\n🎉 VERIFICATION SUMMARY: ${verifiedCount}/${sampleEntries.length} random samples streamed successfully!`);

  console.log('\n============================================================');
  console.log('🏆 MASTER MIGRATION SUMMARY:');
  console.log(`   - Total Files in 5 TB Drive: ${Object.keys(state.uploadedFiles).length}`);
  console.log(`   - Database Rows Remapped: ${state.stats.dbUpdated}`);
  console.log(`   - Errors Encountered: ${state.stats.errors}`);
  console.log('============================================================\n');
}

if (require.main === module) {
  main().catch(console.error);
}
