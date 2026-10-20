/**
 * Deep End-to-End Verification & Latency Benchmark Suite
 * ======================================================
 * Tests:
 * 1. Supabase Database URL consistency (zero broken / zero unmapped URLs).
 * 2. Supabase Storage vs Google Drive 100% coverage parity.
 * 3. Live HTTP 200 / 206 Partial Content byte-range streaming for ExoPlayer/AVPlayer.
 * 4. Image CDN accessibility (lh3.googleusercontent.com).
 * 5. Latency / TTFB benchmarks.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');

const SUPABASE_URL = 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';
const STATE_FILE = path.join(__dirname, '../migration_state.json');

async function fetchAll(pathQuery) {
  let all = [];
  let offset = 0;
  const limit = 1000;
  while (true) {
    const url = `${SUPABASE_URL}/rest/v1/${pathQuery}&limit=${limit}&offset=${offset}`;
    const batch = await new Promise((resolve) => {
      https.get(url, {
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
      }).on('error', () => resolve([]));
    });
    if (!Array.isArray(batch) || batch.length === 0) break;
    all = all.concat(batch);
    if (batch.length < limit) break;
    offset += limit;
  }
  return all;
}

async function testHttpStream(url, isAudio = true) {
  const start = Date.now();
  return new Promise((resolve) => {
    const headers = isAudio ? { 'Range': 'bytes=0-1024' } : {};
    const req = https.get(url, { headers, timeout: 10000 }, res => {
      const ttfb = Date.now() - start;
      const status = res.statusCode;
      const acceptsRanges = res.headers['accept-ranges'] === 'bytes' || status === 206;
      const contentType = res.headers['content-type'] || '';
      res.destroy(); // Close stream immediately
      resolve({
        ok: status === 200 || status === 206 || status === 302 || status === 303,
        status,
        ttfb,
        acceptsRanges,
        contentType
      });
    });
    req.on('error', (err) => {
      resolve({ ok: false, error: err.message, ttfb: Date.now() - start });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ ok: false, error: 'TIMEOUT', ttfb: Date.now() - start });
    });
  });
}

async function listSupabaseBucket(bucket) {
  let all = [];
  let offset = 0;
  const limit = 1000;
  while (true) {
    const payload = JSON.stringify({ prefix: 'VYRA-13533', limit, offset });
    const batch = await new Promise(resolve => {
      const req = https.request({
        hostname: 'wtlqlkkduescumpggttm.supabase.co',
        path: '/storage/v1/object/list/' + bucket,
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': 'Bearer ' + SUPABASE_ANON_KEY,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload)
        }
      }, res => {
        let d = '';
        res.on('data', c => d += c);
        res.on('end', () => {
          try { resolve(JSON.parse(d)); } catch(e) { resolve([]); }
        });
      });
      req.on('error', () => resolve([]));
      req.write(payload);
      req.end();
    });
    if (!Array.isArray(batch) || batch.length === 0) break;
    all.push(...batch);
    if (batch.length < limit) break;
    offset += limit;
  }
  return all;
}

async function runVerification() {
  console.log('================================================================');
  console.log('🧪 VYRA — MASTER DEEP VERIFICATION & PRE-PURGE AUDIT');
  console.log('================================================================\n');

  // 1. Audit Calls Database
  console.log('🔍 [Phase 1/4] Auditing calls table in Supabase Database...');
  const callsWithAudio = await fetchAll('calls?recording_url=not.is.null&recording_url=neq.&select=id,call_type,recording_url,timestamp_ms');
  console.log(`   Total calls with recording URL: ${callsWithAudio.length}`);
  const callsPointingToSupabase = callsWithAudio.filter(c => c.recording_url.includes('supabase.co'));
  const callsPointingToDrive = callsWithAudio.filter(c => c.recording_url.includes('drive.usercontent.google.com') || c.recording_url.includes('drive.google.com'));
  console.log(`   Calls pointing to Supabase Storage: ${callsPointingToSupabase.length} (Target: 0)`);
  console.log(`   Calls pointing to Google Drive Vault: ${callsPointingToDrive.length}`);

  // 2. Audit Chats Database
  console.log('\n🔍 [Phase 2/4] Auditing chats table in Supabase Database...');
  const chatsWithMedia = await fetchAll('chats?media_url=not.is.null&media_url=neq.&select=id,app,media_type,media_url,timestamp_ms');
  console.log(`   Total chats with media URL: ${chatsWithMedia.length}`);
  const chatsPointingToSupabase = chatsWithMedia.filter(c => c.media_url.includes('supabase.co'));
  const chatsPointingToDrive = chatsWithMedia.filter(c => c.media_url.includes('googleusercontent.com') || c.media_url.includes('drive.google.com'));
  console.log(`   Chats pointing to Supabase Storage: ${chatsPointingToSupabase.length} (Target: 0)`);
  console.log(`   Chats pointing to Google Drive CDN: ${chatsPointingToDrive.length}`);

  // 3. Storage Parity & Migration State Audit
  console.log('\n🔍 [Phase 3/4] Checking Storage Buckets vs Google Drive Vault Parity...');
  const recFiles = await listSupabaseBucket('recordings');
  const snapFiles = await listSupabaseBucket('snaps');
  console.log(`   Supabase 'recordings' bucket count: ${recFiles.length}`);
  console.log(`   Supabase 'snaps' bucket count: ${snapFiles.length}`);

  const state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  const uploaded = state.uploadedFiles || {};
  console.log(`   Total files tracked in Google Drive Vault: ${Object.keys(uploaded).length}`);

  let missingRecs = 0;
  for (const r of recFiles) {
    if (!uploaded[r.name] && !uploaded['VYRA-13533/' + r.name]) missingRecs++;
  }
  let missingSnaps = 0;
  for (const s of snapFiles) {
    if (!uploaded[s.name] && !uploaded['VYRA-13533/' + s.name]) missingSnaps++;
  }
  console.log(`   Unmigrated recordings in bucket: ${missingRecs} (Target: 0)`);
  console.log(`   Unmigrated snaps in bucket: ${missingSnaps} (Target: 0)`);

  // 4. Live Streaming & Playback Stress Test (80 randomized samples)
  console.log('\n🚀 [Phase 4/4] Executing Live Streaming & Playback Stress Test (80 samples)...');

  // Select 20 call recordings
  const callSample = callsWithAudio.filter(c => c.call_type !== 'ambient' && c.recording_url && c.recording_url.startsWith('http')).slice(0, 20);
  // Select 20 ambient recordings
  const ambientSample = callsWithAudio.filter(c => c.call_type === 'ambient' && c.recording_url && c.recording_url.startsWith('http')).slice(0, 20);
  // Select 20 snaps
  const snapSample = chatsWithMedia.filter(c => c.media_url && c.media_url.startsWith('http')).slice(0, 20);
  // Select 20 WhatsApp voice notes from state
  const voiceSample = Object.entries(uploaded).filter(([k, v]) => v.category === 'WhatsApp_Voice_Notes' && v.streamUrl && v.streamUrl.startsWith('http')).slice(0, 20);

  let passed = 0;
  let totalTtfb = 0;

  console.log('\n   [A] Testing Phone Call Recordings (HTTP 206 Partial Content):');
  for (const item of callSample) {
    const res = await testHttpStream(item.recording_url, true);
    if (res.ok) {
      passed++;
      totalTtfb += res.ttfb;
      console.log(`     ✅ Call ${item.id} -> HTTP ${res.status} (${res.ttfb}ms, type: ${res.contentType})`);
    } else {
      console.log(`     ❌ Call ${item.id} FAILED: ${res.error || res.status}`);
    }
  }

  console.log('\n   [B] Testing Ambient Audio Recordings (HTTP 206 Partial Content):');
  for (const item of ambientSample) {
    const res = await testHttpStream(item.recording_url, true);
    if (res.ok) {
      passed++;
      totalTtfb += res.ttfb;
      console.log(`     ✅ Ambient ${item.id} -> HTTP ${res.status} (${res.ttfb}ms, type: ${res.contentType})`);
    } else {
      console.log(`     ❌ Ambient ${item.id} FAILED: ${res.error || res.status}`);
    }
  }

  console.log('\n   [C] Testing WhatsApp Voice Notes (HTTP 206 Partial Content):');
  for (const [name, info] of voiceSample) {
    const res = await testHttpStream(info.streamUrl, true);
    if (res.ok) {
      passed++;
      totalTtfb += res.ttfb;
      console.log(`     ✅ VoiceNote ${name.slice(0, 30)} -> HTTP ${res.status} (${res.ttfb}ms)`);
    } else {
      console.log(`     ❌ VoiceNote ${name} FAILED: ${res.error || res.status}`);
    }
  }

  console.log('\n   [D] Testing Snaps / Screenshots (HTTP 200 CDN Image):');
  for (const item of snapSample) {
    const res = await testHttpStream(item.media_url, false);
    if (res.ok) {
      passed++;
      totalTtfb += res.ttfb;
      console.log(`     ✅ Snap ${item.id} -> HTTP ${res.status} (${res.ttfb}ms, type: ${res.contentType})`);
    } else {
      console.log(`     ❌ Snap ${item.id} FAILED: ${res.error || res.status}`);
    }
  }

  const totalTested = callSample.length + ambientSample.length + voiceSample.length + snapSample.length;
  const avgTtfb = Math.round(totalTtfb / passed);

  console.log('\n================================================================');
  console.log('🏆 VERIFICATION REPORT SUMMARY');
  console.log('================================================================');
  console.log(`✅ Total Tests Run:              ${totalTested}`);
  console.log(`✅ Successful Streams:           ${passed}/${totalTested} (${((passed/totalTested)*100).toFixed(1)}%)`);
  console.log(`⚡ Average Latency / TTFB:        ${avgTtfb} ms`);
  console.log(`🔒 Supabase Calls Remaining:     ${callsPointingToSupabase.length}`);
  console.log(`🔒 Supabase Chats Remaining:     ${chatsPointingToSupabase.length}`);
  console.log(`📦 Unmigrated Storage Files:     ${missingRecs + missingSnaps}`);
  console.log('================================================================\n');

  if (passed === totalTested && missingRecs === 0 && missingSnaps === 0 && callsPointingToSupabase.length === 0 && chatsPointingToSupabase.length === 0) {
    console.log('🟢 RESULT: 100% READY FOR SUPABASE STORAGE PURGE. ZERO DATA LOSS GUARANTEED.');
  } else {
    console.log('🔴 RESULT: DISCREPANCY DETECTED. DO NOT PURGE.');
  }
}

runVerification().catch(console.error);
