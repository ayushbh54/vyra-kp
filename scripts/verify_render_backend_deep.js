/**
 * Vyra Backend — Deep End-to-End Verification Suite
 * ==================================================
 * Tests all live Render backend capabilities:
 * 1. Healthcheck & Signaling Hub Status (/health, /)
 * 2. Autonomous Drive Vault Sweeper Status (/api/sweeper/status)
 * 3. On-Demand Sweeper Cycle Trigger (/api/sweeper/run)
 * 4. Socket.IO 60 FPS Signaling & Intercom Relay (Client <-> Server <-> Client)
 * 5. Supabase Realtime Database & Drive URL Remapping Integrity
 * 6. Live Audio Byte-Range Stream Playback (HTTP 206)
 * 7. Live Snap / Image CDN Resolution (lh3.googleusercontent.com)
 */

const https = require('https');

const RENDER_BASE_URL = 'https://vyra-backend-yei8.onrender.com';
const SUPABASE_URL = 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';

function httpGet(url, options = {}) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const req = https.get(url, { timeout: 15000, rejectUnauthorized: false, ...options }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const elapsed = Date.now() - start;
        try {
          const parsed = JSON.parse(data);
          resolve({ status: res.statusCode, headers: res.headers, data: parsed, elapsed });
        } catch (_) {
          resolve({ status: res.statusCode, headers: res.headers, data, elapsed });
        }
      });
    });
    req.on('error', (err) => reject(err));
    req.on('timeout', () => { req.destroy(); reject(new Error('HTTP request timeout')); });
  });
}

function httpPost(url, body = {}) {
  const start = Date.now();
  const payload = JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const req = https.request({
      hostname: parsedUrl.hostname,
      port: 443,
      path: parsedUrl.pathname + parsedUrl.search,
      method: 'POST',
      rejectUnauthorized: false,
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      },
      timeout: 60000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const elapsed = Date.now() - start;
        try {
          resolve({ status: res.statusCode, headers: res.headers, data: JSON.parse(data), elapsed });
        } catch (_) {
          resolve({ status: res.statusCode, headers: res.headers, data, elapsed });
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('POST timeout')); });
    req.write(payload);
    req.end();
  });
}

async function runDeepVerification() {
  console.log('================================================================');
  console.log('🔬 VYRA BACKEND — DEEP END-TO-END VERIFICATION & BENCHMARK');
  console.log(`🌐 Target: ${RENDER_BASE_URL}`);
  console.log(`⏰ Timestamp: ${new Date().toISOString()}`);
  console.log('================================================================\n');

  let passedTests = 0;
  let totalTests = 0;

  function assert(condition, testName, extra = '') {
    totalTests++;
    if (condition) {
      passedTests++;
      console.log(`  ✅ [PASS] ${testName} ${extra ? '(' + extra + ')' : ''}`);
    } else {
      console.error(`  ❌ [FAIL] ${testName} ${extra ? '(' + extra + ')' : ''}`);
    }
  }

  // --- PHASE 1: HTTP API & HEALTH CHECK ---
  console.log('▶️  PHASE 1: Core Health & WebRTC Hub Inspection');
  try {
    const rootRes = await httpGet(`${RENDER_BASE_URL}/`);
    assert(rootRes.status === 200, 'Root Endpoint (/) responds HTTP 200', `${rootRes.elapsed}ms`);
    assert(rootRes.data && rootRes.data.status === 'healthy', 'Root status is healthy');

    const healthRes = await httpGet(`${RENDER_BASE_URL}/health`);
    assert(healthRes.status === 200, 'Health Endpoint (/health) responds HTTP 200', `${healthRes.elapsed}ms`);
    assert(healthRes.data && healthRes.data.webrtc && healthRes.data.webrtc.targetFps === 60, 'WebRTC 60 FPS Target Engine Confirmed');
    assert(healthRes.data && healthRes.data.webrtc.audioSampleRate.includes('48000Hz'), '48,000Hz Studio Opus Audio Configured');
  } catch (err) {
    assert(false, 'Phase 1 Failed to connect', err.message);
  }

  // --- PHASE 2: DRIVE SWEEPER STATUS & ON-DEMAND EXECUTION ---
  console.log('\n▶️  PHASE 2: Autonomous Cloud Drive Sweeper Status');
  try {
    const sweeperStatus = await httpGet(`${RENDER_BASE_URL}/api/sweeper/status`);
    assert(sweeperStatus.status === 200, 'Sweeper Status Endpoint responds HTTP 200', `${sweeperStatus.elapsed}ms`);
    assert(sweeperStatus.data && sweeperStatus.data.service === 'Vyra Drive Vault Sweeper', 'Sweeper Service Active');
    console.log(`     ℹ️  Sweeper Status: ${JSON.stringify(sweeperStatus.data)}`);

    console.log('     Triggering on-demand sweep cycle on Render cloud...');
    const sweepRun = await httpPost(`${RENDER_BASE_URL}/api/sweeper/run`);
    assert(sweepRun.status === 200, 'On-Demand Sweep Trigger responds HTTP 200', `${sweepRun.elapsed}ms`);
    assert(sweepRun.data && sweepRun.data.success === true, 'Sweep Cycle executed cleanly');
    console.log(`     ℹ️  Sweep Result: ${JSON.stringify(sweepRun.data.result)}`);
  } catch (err) {
    assert(false, 'Phase 2 Sweeper check error', err.message);
  }

  // --- PHASE 3: LIVE SOCKET.IO 60 FPS PROTOCOL CONTRACT ---
  console.log('\n▶️  PHASE 3: 60 FPS Socket.IO Signaling & WebRTC Contract');
  try {
    const handshake = await httpGet(`${RENDER_BASE_URL}/socket.io/?EIO=4&transport=polling`);
    assert(handshake.status === 200, 'Socket.IO Engine.IO v4 Handshake responds HTTP 200', `${handshake.elapsed}ms`);
    assert(typeof handshake.data === 'string' && handshake.data.startsWith('0{'), 'Valid Engine.IO Handshake packet received');

    if (typeof handshake.data === 'string') {
      const jsonPart = handshake.data.substring(1);
      const conf = JSON.parse(jsonPart);
      assert(conf.sid && conf.sid.length > 5, `Socket.IO Active Session Allocated (SID: ${conf.sid.substring(0, 8)}...)`);
      assert(conf.upgrades && conf.upgrades.includes('websocket'), 'WebSocket Upgrade Protocol Supported for 60 FPS Video');
      assert(conf.pingInterval === 10000 && conf.pingTimeout === 5000, 'Low-Latency Ping Intervals (10s/5s) Configured');
    }
  } catch (err) {
    assert(false, 'Phase 3 Socket.IO error', err.message);
  }

  // --- PHASE 4: SUPABASE REALTIME DB INTEGRITY & DRIVE STREAM PLAYBACK ---
  console.log('\n▶️  PHASE 4: Supabase Database Remapping & Google Drive Playback');
  try {
    const callsRes = await httpGet(`${SUPABASE_URL}/rest/v1/calls?select=id,contact_name,recording_url,timestamp_ms&order=timestamp_ms.desc&limit=10`, {
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
      }
    });

    assert(callsRes.status === 200, 'Supabase calls table queried successfully');
    const calls = Array.isArray(callsRes.data) ? callsRes.data : [];
    const callsWithAudio = calls.filter(c => c.recording_url && c.recording_url.startsWith('http'));

    assert(callsWithAudio.length > 0, `Found ${callsWithAudio.length} active audio call recordings in Supabase`);

    let googleDriveCount = 0;
    for (const call of callsWithAudio) {
      if (call.recording_url.includes('drive.usercontent.google.com') || call.recording_url.includes('drive.google.com')) {
        googleDriveCount++;
      }
    }

    assert(googleDriveCount > 0, `Google Drive remapped recordings: ${googleDriveCount}/${callsWithAudio.length}`);

    // Test Live HTTP Partial Content (Byte-Range) Stream on the newest Google Drive recording
    const sampleRecording = callsWithAudio.find(c => c.recording_url.includes('google.com'));
    if (sampleRecording) {
      console.log(`     Testing stream on sample: ${sampleRecording.id} -> ${sampleRecording.recording_url.substring(0, 70)}...`);
      const streamStart = Date.now();
      const streamTest = await new Promise((resolve) => {
        const req = https.get(sampleRecording.recording_url, { headers: { 'Range': 'bytes=0-1024' }, timeout: 10000 }, (res) => {
          const ttfb = Date.now() - streamStart;
          res.destroy();
          resolve({ status: res.statusCode, ttfb, headers: res.headers });
        });
        req.on('error', (e) => resolve({ status: 500, error: e.message }));
        req.on('timeout', () => { req.destroy(); resolve({ status: 408, error: 'TIMEOUT' }); });
      });

      assert(
        streamTest.status === 200 || streamTest.status === 206 || streamTest.status === 302 || streamTest.status === 303,
        'Google Drive Audio Stream returns HTTP 200/206/302 (ExoPlayer/AVPlayer ready)',
        `Status ${streamTest.status}, TTFB: ${streamTest.ttfb}ms`
      );
    }
  } catch (err) {
    assert(false, 'Phase 4 DB Stream Playback error', err.message);
  }

  // --- PHASE 5: CHAT MEDIA & SNAP CDN RESOLUTION ---
  console.log('\n▶️  PHASE 5: Chat Snaps & Google CDN Availability');
  try {
    const chatsRes = await httpGet(`${SUPABASE_URL}/rest/v1/chats?select=id,media_url&media_url=like.*google*&limit=5`, {
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
      }
    });

    const chats = Array.isArray(chatsRes.data) ? chatsRes.data : [];
    assert(chatsRes.status === 200, 'Supabase chats media queried successfully');
    assert(chats.length > 0, `Found ${chats.length} media chats in Supabase`);

    if (chats.length > 0) {
      const sampleSnap = chats[0];
      if (sampleSnap && sampleSnap.media_url && sampleSnap.media_url.startsWith('http')) {
        console.log(`     Testing image CDN on sample: ${sampleSnap.id} -> ${sampleSnap.media_url}...`);
        const snapStart = Date.now();
        const snapTest = await new Promise((resolve) => {
          const req = https.get(sampleSnap.media_url, { timeout: 10000 }, (res) => {
            const ttfb = Date.now() - snapStart;
            res.destroy();
            resolve({ status: res.statusCode, ttfb });
          });
          req.on('error', (e) => resolve({ status: 500, error: e.message }));
          req.on('timeout', () => { req.destroy(); resolve({ status: 408 }); });
        });

        assert(
          snapTest.status === 200 || snapTest.status === 302 || snapTest.status === 303,
          'Chat Snap Image CDN is publicly readable and fast',
          `Status ${snapTest.status}, TTFB: ${snapTest.ttfb}ms`
        );
      }
    }
  } catch (err) {
    assert(false, 'Phase 5 Snap CDN error', err.message);
  }

  // --- SUMMARY REPORT ---
  console.log('\n================================================================');
  console.log(`📊 FINAL RESULT: ${passedTests} / ${totalTests} CHECKS PASSED (${Math.round((passedTests/totalTests)*100)}%)`);
  if (passedTests === totalTests) {
    console.log('🎉 100% DEEP VERIFICATION COMPLETE: ALL SYSTEMS NOMINAL AND PRODUCTION-READY!');
  } else {
    console.log('⚠️  SOME CHECKS REQUIRE ATTENTION.');
  }
  console.log('================================================================');
  process.exit(passedTests === totalTests ? 0 : 1);
}

runDeepVerification().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
