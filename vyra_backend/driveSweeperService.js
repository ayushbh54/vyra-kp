/**
 * Vyra Parental Control Suite — Instant Realtime Cloud Drive Media Relay
 * ======================================================================
 * Runs inside vyra_backend (Render cloud 24/7).
 *
 * 1. REALTIME WEBSOCKET LISTENER (@supabase/supabase-js):
 *    Listens directly to PostgreSQL INSERT events on 'calls' and 'chats' tables.
 *    The millisecond the child app saves an audio recording or snap:
 *    ➔ Instant event triggers in vyra_backend (0 delay).
 *    ➔ Streams the file into the 5 TB Google Drive Vault ('Vyra_Vault').
 *    ➔ Updates Supabase database row ('calls', 'chats') to high-speed direct Drive URL.
 *    ➔ If AUTO_PURGE_SUPABASE_STORAGE=true, purges from Supabase Storage.
 *
 * 2. AUTONOMOUS BACKGROUND HEARTBEAT (every 30s):
 *    Ensures zero missed files even during rare mobile reconnects or network packet drops.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { createClient } = require('@supabase/supabase-js');
const {
  VAULT_CONFIG,
  getDriveAccessToken,
  uploadToDrive,
  ensurePublicRead,
  updateSupabaseRow,
  fetchSupabaseRow,
  verifyUrlStream,
  deleteSupabaseStorageFile
} = require('./driveService');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';
const CHILD_ID = process.env.CHILD_ID || 'VYRA-13533';

let isSweeping = false;
let lastSweepTime = null;
let totalSweptCount = 0;
const processedFilesSet = new Set();
let realtimeClient = null;

function loadKnownState() {
  const statePath = path.join(__dirname, '../migration_state.json');
  if (fs.existsSync(statePath)) {
    try {
      const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
      if (state.uploadedFiles) {
        Object.keys(state.uploadedFiles).forEach(k => {
          processedFilesSet.add(k);
          if (k.includes('/')) processedFilesSet.add(k.split('/').pop());
        });
      }
    } catch (_) {}
  }
}
loadKnownState();

function recordProcessedFile(fileName, streamUrl) {
  processedFilesSet.add(fileName);
  try {
    const statePath = path.join(__dirname, '../migration_state.json');
    let state = { uploadedFiles: {} };
    if (fs.existsSync(statePath)) {
      state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
      if (!state.uploadedFiles) state.uploadedFiles = {};
    }
    state.uploadedFiles[fileName] = streamUrl;
    state.lastUpdated = new Date().toISOString();
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2), 'utf8');
  } catch (_) {}
}

function extractFilename(urlOrName) {
  if (!urlOrName) return '';
  const decoded = decodeURIComponent(urlOrName);
  const parts = decoded.split('/');
  return parts[parts.length - 1].split('?')[0].trim();
}

async function downloadFileBuffer(bucket, remotePath) {
  const encoded = remotePath.split('/').map(encodeURIComponent).join('/');
  const url = `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${encoded}`;
  return new Promise((resolve, reject) => {
    const req = https.get(url, { timeout: 90000 }, res => {
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Download timeout (90s)')); });
  });
}

async function listBucketFiles(bucket, prefix = CHILD_ID) {
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

/**
 * Instant Realtime Relay for a single Call Recording
 */
async function relaySingleAudio(row) {
  const fileName = extractFilename(row.recording_url) || (row.id ? `${row.id}.m4a` : '');
  if (!fileName || processedFilesSet.has(fileName)) return;

  try {
    const token = await getDriveAccessToken();
    const autoPurge = process.env.AUTO_PURGE_SUPABASE_STORAGE === 'true' || process.env.PURGE_STORAGE === 'true';

    const remotePath = `${CHILD_ID}/${fileName}`;
    const buf = await downloadFileBuffer('recordings', remotePath).catch(() => downloadFileBuffer('recordings', fileName));
    const isVoiceNote = fileName.endsWith('.opus');
    const folderId = isVoiceNote ? VAULT_CONFIG.folders.WhatsApp_Voice_Notes : VAULT_CONFIG.folders.Call_Recordings;

    const uploaded = await uploadToDrive(token, fileName, buf, isVoiceNote ? 'audio/ogg' : 'audio/mp4', folderId);
    await ensurePublicRead(token, uploaded.fileId);

    const ok = await verifyUrlStream(uploaded.streamUrl);
    if (ok) {
      await updateSupabaseRow('calls', 'id', row.id, { recording_url: uploaded.streamUrl });
      recordProcessedFile(fileName, uploaded.streamUrl);
      totalSweptCount++;

      if (autoPurge) {
        await deleteSupabaseStorageFile('recordings', remotePath);
      }
      console.log(`⚡ [Realtime Relay] Instant audio relay complete: ${fileName} ➔ Drive (${uploaded.streamUrl})`);
    }
  } catch (err) {
    console.error(`[Realtime Relay Audio Error] ${fileName}:`, err.message);
  }
}

/**
 * Instant Realtime Relay for a single Chat Media (Snap / Photo)
 */
async function relaySingleChatMedia(row) {
  const fileName = extractFilename(row.media_url);
  if (!fileName || processedFilesSet.has(fileName)) return;

  try {
    const token = await getDriveAccessToken();
    const autoPurge = process.env.AUTO_PURGE_SUPABASE_STORAGE === 'true' || process.env.PURGE_STORAGE === 'true';

    const remotePath = `${CHILD_ID}/${fileName}`;
    const buf = await downloadFileBuffer('snaps', remotePath).catch(() => downloadFileBuffer('snaps', fileName));

    const uploaded = await uploadToDrive(token, fileName, buf, 'image/jpeg', VAULT_CONFIG.folders.Screenshots_and_Snaps);
    await ensurePublicRead(token, uploaded.fileId);

    const ok = await verifyUrlStream(uploaded.directCdnUrl);
    if (ok) {
      await updateSupabaseRow('chats', 'id', row.id, { media_url: uploaded.directCdnUrl });
      recordProcessedFile(fileName, uploaded.directCdnUrl);
      totalSweptCount++;

      if (autoPurge) {
        await deleteSupabaseStorageFile('snaps', remotePath);
      }
      console.log(`⚡ [Realtime Relay] Instant snap relay complete: ${fileName} ➔ Drive (${uploaded.directCdnUrl})`);
    }
  } catch (err) {
    console.error(`[Realtime Relay Snap Error] ${fileName}:`, err.message);
  }
}

/**
 * Full Sweeper Cycle (Runs on startup & periodic 30s heartbeat fallback)
 */
async function runSweepCycle() {
  if (isSweeping) return { status: 'already_running' };
  isSweeping = true;
  lastSweepTime = new Date().toISOString();

  let token;
  try {
    token = await getDriveAccessToken();
  } catch (err) {
    isSweeping = false;
    return { status: 'auth_error', message: err.message };
  }

  const autoPurge = process.env.AUTO_PURGE_SUPABASE_STORAGE !== 'false';
  let processedAudio = 0;
  let processedSnaps = 0;

  try {
    // 1. Process Recordings Bucket
    const recs = await listBucketFiles('recordings', CHILD_ID);
    for (const item of recs) {
      if (!item.name || item.name.endsWith('/')) continue;
      const remotePath = `${CHILD_ID}/${item.name}`;

      if (processedFilesSet.has(item.name)) {
        if (autoPurge) {
          await deleteSupabaseStorageFile('recordings', remotePath);
        }
        continue;
      }

      const rowId = item.name.replace(/\.[^/.]+$/, '');
      const existingRow = await fetchSupabaseRow('calls', rowId);
      if (existingRow && existingRow.recording_url && (existingRow.recording_url.includes('google.com') || existingRow.recording_url.includes('googleusercontent.com'))) {
        processedFilesSet.add(item.name);
        if (autoPurge) {
          await deleteSupabaseStorageFile('recordings', remotePath);
        }
        continue;
      }

      const oldUrl = `${SUPABASE_URL}/storage/v1/object/public/recordings/${remotePath}`;

      try {
        const buf = await downloadFileBuffer('recordings', remotePath);
        const isVoiceNote = item.name.endsWith('.opus');
        const folderId = isVoiceNote ? VAULT_CONFIG.folders.WhatsApp_Voice_Notes : VAULT_CONFIG.folders.Call_Recordings;
        const uploaded = await uploadToDrive(token, item.name, buf, isVoiceNote ? 'audio/ogg' : 'audio/mp4', folderId);
        await ensurePublicRead(token, uploaded.fileId);

        const ok = await verifyUrlStream(uploaded.streamUrl);
        if (ok) {
          await updateSupabaseRow('calls', 'id', rowId, { recording_url: uploaded.streamUrl });
          await updateSupabaseRow('calls', 'recording_url', oldUrl, { recording_url: uploaded.streamUrl });

          recordProcessedFile(item.name, uploaded.streamUrl);
          if (autoPurge) {
            await deleteSupabaseStorageFile('recordings', remotePath);
          }
          processedAudio++;
          totalSweptCount++;
          console.log(`[Drive Sweeper] Relayed audio: ${item.name} ➔ Drive`);
        }
      } catch (itemErr) {
        console.error(`[Drive Sweeper] Error on ${item.name}:`, itemErr.message);
      }
    }

    // 2. Process Snaps Bucket
    const snaps = await listBucketFiles('snaps', CHILD_ID);
    for (const item of snaps) {
      if (!item.name || item.name.endsWith('/')) continue;
      const remotePath = `${CHILD_ID}/${item.name}`;

      if (processedFilesSet.has(item.name)) {
        if (autoPurge) {
          await deleteSupabaseStorageFile('snaps', remotePath);
        }
        continue;
      }

      const rowId = item.name.replace(/\.[^/.]+$/, '');
      const existingChatRow = await fetchSupabaseRow('chats', rowId);
      if (existingChatRow && existingChatRow.media_url && (existingChatRow.media_url.includes('google.com') || existingChatRow.media_url.includes('googleusercontent.com'))) {
        processedFilesSet.add(item.name);
        if (autoPurge) {
          await deleteSupabaseStorageFile('snaps', remotePath);
        }
        continue;
      }

      const oldUrl = `${SUPABASE_URL}/storage/v1/object/public/snaps/${remotePath}`;

      try {
        const buf = await downloadFileBuffer('snaps', remotePath);
        const uploaded = await uploadToDrive(token, item.name, buf, 'image/jpeg', VAULT_CONFIG.folders.Screenshots_and_Snaps);
        await ensurePublicRead(token, uploaded.fileId);

        const ok = await verifyUrlStream(uploaded.directCdnUrl);
        if (ok) {
          await updateSupabaseRow('chats', 'media_url', oldUrl, { media_url: uploaded.directCdnUrl });

          recordProcessedFile(item.name, uploaded.directCdnUrl);
          if (autoPurge) {
            await deleteSupabaseStorageFile('snaps', remotePath);
          }
          processedSnaps++;
          totalSweptCount++;
          console.log(`[Drive Sweeper] Relayed snap: ${item.name} ➔ Drive`);
        }
      } catch (itemErr) {
        console.error(`[Drive Sweeper] Error on ${item.name}:`, itemErr.message);
      }
    }

    isSweeping = false;
    return {
      status: 'success',
      lastSweepTime,
      processedAudio,
      processedSnaps,
      totalSweptCount,
      autoPurge
    };
  } catch (err) {
    isSweeping = false;
    console.error('[Drive Sweeper Error]', err);
    return { status: 'error', message: err.message };
  }
}

/**
 * Initializes both the Instant Realtime Listener and the 30s Heartbeat
 */
function initDriveSweeper(intervalMs = 30000) {
  console.log(`[Drive Sweeper] Initializing Realtime Relay & 30s Heartbeat...`);

  // Seed state from Supabase so redundant uploads never happen
  try {
    const key = SUPABASE_ANON_KEY;
    const req = https.get({
      hostname: 'wtlqlkkduescumpggttm.supabase.co',
      path: '/rest/v1/calls?select=recording_url&recording_url=like.*google*&limit=500',
      headers: { apikey: key, Authorization: 'Bearer ' + key },
      timeout: 5000
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try {
          const arr = JSON.parse(d);
          if (Array.isArray(arr)) {
            arr.forEach(r => {
              if (r.recording_url) {
                const fn = extractFilename(r.recording_url);
                if (fn) processedFilesSet.add(fn);
              }
            });
            console.log(`[Drive Sweeper] Seeded ${processedFilesSet.size} known files from database`);
          }
        } catch (_) {}
      });
    });
    req.on('error', () => {});
    req.on('timeout', () => req.destroy());
  } catch (_) {}

  // 1. Start Instant Realtime WebSocket listener
  try {
    realtimeClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    realtimeClient.channel('realtime_drive_vault_relay')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'calls' }, (payload) => {
        const row = payload.new;
        if (row && row.recording_url && (row.recording_url.includes('supabase.co') || !row.recording_url.startsWith('http'))) {
          console.log(`⚡ [Drive Realtime] Instant Call event detected for ${row.id}. Relaying immediately...`);
          relaySingleAudio(row);
        }
      })
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chats' }, (payload) => {
        const row = payload.new;
        if (row && row.media_url && row.media_url.includes('supabase.co')) {
          console.log(`⚡ [Drive Realtime] Instant Chat Media event detected for ${row.id}. Relaying immediately...`);
          relaySingleChatMedia(row);
        }
      })
      .subscribe((status, err) => {
        console.log(`⚡ [Drive Realtime] WebSocket connection active. Status: ${status}`);
      });
  } catch (realtimeErr) {
    console.error('[Drive Realtime Init Error]', realtimeErr);
  }

  // 2. Initial sweep after 2s
  setTimeout(() => {
    runSweepCycle().catch(e => console.error('[Drive Sweeper initial run error]', e));
  }, 2000);

  // 3. Fallback periodic heartbeat (every 30 seconds)
  setInterval(() => {
    runSweepCycle().catch(e => console.error('[Drive Sweeper heartbeat error]', e));
  }, intervalMs);
}

module.exports = {
  initDriveSweeper,
  runSweepCycle,
  getSweeperStatus: () => ({
    isSweeping,
    lastSweepTime,
    totalSweptCount,
    autoPurgeEnabled: process.env.AUTO_PURGE_SUPABASE_STORAGE === 'true' || process.env.PURGE_STORAGE === 'true'
  })
};
