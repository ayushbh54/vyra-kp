/**
 * Vyra Realtime Media Sweeper & Auto-Relay to 5 TB Google Drive
 * ==============================================================
 * Continuously watches Supabase Storage buckets ('recordings', 'snaps').
 * Whenever the child app uploads a new call recording, voice note, or snap:
 * 1. Automatically streams the file into the user's 5 TB Google Drive.
 * 2. Updates the Supabase database row ('calls', 'chats') with the Drive streaming link.
 * 3. Immediately purges the file from Supabase Storage if PURGE_STORAGE=true.
 *
 * Result: 100% backward compatibility with the existing child app, zero maintenance, zero storage billing.
 */

const https = require('https');
const path = require('path');
const fs = require('fs');
const {
  VAULT_CONFIG,
  getDriveAccessToken,
  uploadToDrive,
  ensurePublicRead,
  updateSupabaseRow,
  deleteSupabaseStorageFile,
  verifyUrlStream
} = require('./drive_service');

const SUPABASE_URL = 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';
const STATE_FILE = path.join(__dirname, '../migration_state.json');

const processedFilesSet = new Set();
let state = { uploadedFiles: {}, stats: {} };

function loadState() {
  if (fs.existsSync(STATE_FILE)) {
    try {
      state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      if (state.uploadedFiles) {
        Object.keys(state.uploadedFiles).forEach(k => {
          processedFilesSet.add(k);
          if (k.includes('/')) processedFilesSet.add(k.split('/').pop());
        });
      }
    } catch (_) {}
  }
}
loadState();

async function listBucketFiles(bucket, prefix = 'VYRA-13533') {
  const payload = JSON.stringify({ prefix, limit: 100, sortBy: { column: 'created_at', order: 'desc' } });
  return new Promise((resolve) => {
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
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try { resolve(JSON.parse(d)); } catch (_) { resolve([]); }
      });
    });
    req.on('error', () => resolve([]));
    req.write(payload);
    req.end();
  });
}

async function downloadFileBuffer(bucket, remotePath) {
  const encoded = remotePath.split('/').map(encodeURIComponent).join('/');
  const url = `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${encoded}`;
  return new Promise((resolve, reject) => {
    https.get(url, res => {
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

async function sweep() {
  let token;
  try {
    token = await getDriveAccessToken();
  } catch (e) {
    console.error('Sweeper auth error:', e.message);
    return;
  }

  const autoPurge = process.env.PURGE_STORAGE === 'true' || process.env.AUTO_PURGE_SUPABASE_STORAGE === 'true';

  // 1. Sweep recordings
  const recs = await listBucketFiles('recordings', 'VYRA-13533');
  for (const item of recs) {
    if (!item.name || item.name.endsWith('/')) continue;
    const remotePath = `VYRA-13533/${item.name}`;

    if (processedFilesSet.has(item.name)) {
      if (autoPurge) {
        await deleteSupabaseStorageFile('recordings', remotePath);
        console.log(`[Sweeper] Purged already-migrated audio: ${item.name}`);
      }
      continue;
    }

    const rowId = item.name.replace(/\.[^/.]+$/, '');
    const oldUrl = `${SUPABASE_URL}/storage/v1/object/public/recordings/${remotePath}`;

    try {
      const buf = await downloadFileBuffer('recordings', remotePath);
      const isVoiceNote = item.name.endsWith('.opus');
      const folderId = isVoiceNote ? VAULT_CONFIG.folders.WhatsApp_Voice_Notes : VAULT_CONFIG.folders.Call_Recordings;
      const uploaded = await uploadToDrive(token, item.name, buf, isVoiceNote ? 'audio/ogg' : 'audio/mp4', folderId);
      await ensurePublicRead(token, uploaded.fileId);

      const verified = await verifyUrlStream(uploaded.streamUrl);
      if (verified) {
        await updateSupabaseRow('calls', 'id', rowId, { recording_url: uploaded.streamUrl });
        await updateSupabaseRow('calls', 'recording_url', oldUrl, { recording_url: uploaded.streamUrl });

        processedFilesSet.add(item.name);
        state.uploadedFiles[item.name] = {
          fileId: uploaded.fileId,
          streamUrl: uploaded.streamUrl,
          cdnUrl: uploaded.directCdnUrl,
          category: isVoiceNote ? 'WhatsApp_Voice_Notes' : 'Call_Recordings',
          supabasePath: remotePath,
          bucket: 'recordings',
          migratedAt: new Date().toISOString()
        };
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));

        if (autoPurge) {
          await deleteSupabaseStorageFile('recordings', remotePath);
          console.log(`[Sweeper] Auto-relayed & purged audio: ${item.name} ➔ Drive`);
        } else {
          console.log(`[Sweeper] Auto-relayed audio: ${item.name} ➔ Drive (Supabase copy preserved)`);
        }
      }
    } catch (e) {
      console.error(`[Sweeper] Error processing ${item.name}:`, e.message);
    }
  }

  // 2. Sweep snaps
  const snaps = await listBucketFiles('snaps', 'VYRA-13533');
  for (const item of snaps) {
    if (!item.name || item.name.endsWith('/')) continue;
    const remotePath = `VYRA-13533/${item.name}`;

    if (processedFilesSet.has(item.name)) {
      if (autoPurge) {
        await deleteSupabaseStorageFile('snaps', remotePath);
        console.log(`[Sweeper] Purged already-migrated snap: ${item.name}`);
      }
      continue;
    }

    const oldUrl = `${SUPABASE_URL}/storage/v1/object/public/snaps/${remotePath}`;

    try {
      const buf = await downloadFileBuffer('snaps', remotePath);
      const uploaded = await uploadToDrive(token, item.name, buf, 'image/jpeg', VAULT_CONFIG.folders.Screenshots_and_Snaps);
      await ensurePublicRead(token, uploaded.fileId);

      const verified = await verifyUrlStream(uploaded.directCdnUrl);
      if (verified) {
        await updateSupabaseRow('chats', 'media_url', oldUrl, { media_url: uploaded.directCdnUrl });

        processedFilesSet.add(item.name);
        state.uploadedFiles[item.name] = {
          fileId: uploaded.fileId,
          streamUrl: uploaded.streamUrl,
          cdnUrl: uploaded.directCdnUrl,
          category: 'Screenshots_and_Snaps',
          supabasePath: remotePath,
          bucket: 'snaps',
          migratedAt: new Date().toISOString()
        };
        fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));

        if (autoPurge) {
          await deleteSupabaseStorageFile('snaps', remotePath);
          console.log(`[Sweeper] Auto-relayed & purged snap: ${item.name} ➔ Drive`);
        } else {
          console.log(`[Sweeper] Auto-relayed snap: ${item.name} ➔ Drive (Supabase copy preserved)`);
        }
      }
    } catch (e) {
      console.error(`[Sweeper] Error processing ${item.name}:`, e.message);
    }
  }
}

if (require.main === module) {
  sweep().then(() => console.log('[Sweeper] Run complete.'));
}

module.exports = { sweep };
