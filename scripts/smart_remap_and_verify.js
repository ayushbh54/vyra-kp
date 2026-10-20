/**
 * Smart Targeted Database URL Remapper & Deep Verifier
 * ===================================================
 * Reads all actual media rows in Supabase 'calls' and 'chats'
 * and updates them to the 5 TB Google Drive streaming URLs in seconds.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { updateSupabaseRow, verifyUrlStream } = require('./drive_service');

const SUPABASE_URL = 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';
const STATE_FILE = path.join(__dirname, '../migration_state.json');

const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
const uploaded = state.uploadedFiles || {};

console.log(`Loaded ${Object.keys(uploaded).length} uploaded Drive files from state.`);

// Normalize filename from URL or path
function extractFilename(val) {
  if (!val) return '';
  const decoded = decodeURIComponent(val);
  const parts = decoded.split('/');
  return parts[parts.length - 1].split('?')[0].trim();
}

async function fetchTableRows(table, filterParam, limit = 1000) {
  let allRows = [];
  let offset = 0;
  while (true) {
    const url = `${SUPABASE_URL}/rest/v1/${table}?${filterParam}&limit=${limit}&offset=${offset}`;
    const rows = await new Promise((resolve) => {
      const req = https.get(url, {
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
        }
      }, res => {
        let d = '';
        res.on('data', c => d += c);
        res.on('end', () => {
          try { resolve(JSON.parse(d)); } catch (_) { resolve([]); }
        });
      });
      req.on('error', () => resolve([]));
    });

    if (!Array.isArray(rows) || rows.length === 0) break;
    allRows = allRows.concat(rows);
    if (rows.length < limit) break;
    offset += limit;
  }
  return allRows;
}

async function runPool(items, limit, fn) {
  let idx = 0;
  let active = 0;
  return new Promise(resolve => {
    if (items.length === 0) return resolve();
    function next() {
      if (idx >= items.length && active === 0) return resolve();
      while (active < limit && idx < items.length) {
        const item = items[idx++];
        active++;
        fn(item).finally(() => {
          active--;
          next();
        });
      }
    }
    next();
  });
}

async function main() {
  console.log('\n============================================================');
  console.log('🔄 VYRA — SMART DATABASE URL REMAPPER & VERIFIER');
  console.log('============================================================\n');

  // 1. Remap calls table
  console.log('📞 [1/3] Remapping calls table recording_url...');
  const calls = await fetchTableRows('calls', 'recording_url=not.is.null&recording_url=neq.');
  console.log(`   Found ${calls.length} calls with recording URLs in database.`);

  let callsUpdated = 0;
  await runPool(calls, 16, async (row) => {
    const fn = extractFilename(row.recording_url);
    const driveInfo = uploaded[fn];
    if (driveInfo && driveInfo.streamUrl && row.recording_url !== driveInfo.streamUrl) {
      const ok = await updateSupabaseRow('calls', 'id', row.id, { recording_url: driveInfo.streamUrl });
      if (ok) callsUpdated++;
    }
  });
  console.log(`✅ Remapped ${callsUpdated} call records to 5 TB Google Drive streaming URLs!\n`);

  // 2. Remap chats table
  console.log('💬 [2/3] Remapping chats table media_url...');
  const chats = await fetchTableRows('chats', 'media_url=not.is.null&media_url=neq.');
  console.log(`   Found ${chats.length} chat messages with media URLs in database.`);

  let chatsUpdated = 0;
  await runPool(chats, 16, async (row) => {
    const fn = extractFilename(row.media_url);
    const driveInfo = uploaded[fn];
    if (driveInfo && driveInfo.cdnUrl && row.media_url !== driveInfo.cdnUrl) {
      const ok = await updateSupabaseRow('chats', 'id', row.id, { media_url: driveInfo.cdnUrl });
      if (ok) chatsUpdated++;
    }
  });
  console.log(`✅ Remapped ${chatsUpdated} chat media URLs to 5 TB Google Drive CDN URLs!\n`);

  // 3. Deep Verification Phase
  console.log('🧪 [3/3] Running Deep End-to-End Playback Verification...');
  
  // Test 5 ambient recordings
  const ambientSample = Object.entries(uploaded).filter(([k]) => k.startsWith('ambient_')).slice(0, 5);
  // Test 5 phone call recordings
  const callSample = Object.entries(uploaded).filter(([k, v]) => v.category === 'Call_Recordings' && !k.startsWith('ambient_')).slice(0, 5);
  // Test 5 WhatsApp voice notes
  const voiceSample = Object.entries(uploaded).filter(([k, v]) => v.category === 'WhatsApp_Voice_Notes').slice(0, 5);
  // Test 5 Snaps / Screenshots
  const snapSample = Object.entries(uploaded).filter(([k, v]) => v.category === 'Screenshots_and_Snaps').slice(0, 5);

  const testQueue = [
    ...ambientSample.map(([fn, info]) => ({ fn, type: 'Ambient Voice Log', url: info.streamUrl })),
    ...callSample.map(([fn, info]) => ({ fn, type: 'Phone Call Recording', url: info.streamUrl })),
    ...voiceSample.map(([fn, info]) => ({ fn, type: 'WhatsApp Voice Note', url: info.streamUrl })),
    ...snapSample.map(([fn, info]) => ({ fn, type: 'Snap / Screenshot', url: info.cdnUrl }))
  ];

  let verified = 0;
  for (const t of testQueue) {
    const ok = await verifyUrlStream(t.url);
    if (ok) {
      verified++;
      console.log(`   ✅ [${t.type}] Stream Verified: ${t.fn}`);
    } else {
      console.log(`   ⚠️ [${t.type}] Warning on: ${t.fn}`);
    }
  }

  console.log(`\n🎉 Deep Verification Result: ${verified}/${testQueue.length} streams 100% playable!`);
  console.log('\n============================================================');
  console.log('🏆 REMAP & VERIFICATION COMPLETE!');
  console.log(`   - Calls Remapped: ${callsUpdated}`);
  console.log(`   - Chats Remapped: ${chatsUpdated}`);
  console.log(`   - Total Files in Drive: ${Object.keys(uploaded).length}`);
  console.log('============================================================\n');
}

main().catch(console.error);
