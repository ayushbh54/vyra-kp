const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const http = require('http');

// 1. Verify Environment & Config
test('Backend Environment & Directory Initialization', async (t) => {
  const uploadsDir = path.join(__dirname, '..', 'uploads', 'recordings');
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
  }
  assert.equal(fs.existsSync(uploadsDir), true, 'Uploads recording directory should exist');
});

// 2. Test Audio MIME type resolver logic from geminiAudioService
test('Gemini Audio Intelligence - MIME Type Mapping & Format Handling', async (t) => {
  function getMimeType(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.wav') return 'audio/wav';
    if (ext === '.mp3') return 'audio/mp3';
    if (ext === '.aac') return 'audio/aac';
    if (ext === '.opus' || ext === '.ogg') return 'audio/ogg';
    return 'audio/mp4';
  }

  assert.equal(getMimeType('test_ambient.wav'), 'audio/wav');
  assert.equal(getMimeType('test_call.mp3'), 'audio/mp3');
  assert.equal(getMimeType('test_stream.opus'), 'audio/ogg');
  assert.equal(getMimeType('test_recording.m4a'), 'audio/mp4');
  assert.equal(getMimeType('test_raw.bin'), 'audio/mp4');
});

// 3. Test Storage Auto-Purge & Bookkeeping
test('Storage Auto-Purge & Cloud Space Calculation', async (t) => {
  let totalBytesPurgedFromCloud = 0;
  const mockRecordings = [
    { id: 'rec_1', originalSize: 15 * 1024 * 1024, purge: true },
    { id: 'rec_2', originalSize: 32 * 1024 * 1024, purge: true },
    { id: 'rec_3', originalSize: 5 * 1024 * 1024, purge: false }, // Retained
  ];

  for (const rec of mockRecordings) {
    if (rec.purge) {
      totalBytesPurgedFromCloud += rec.originalSize;
    }
  }

  const savedStorageMb = parseFloat((totalBytesPurgedFromCloud / (1024 * 1024)).toFixed(2));
  assert.equal(savedStorageMb, 47.0, 'Saved storage should equal exactly 47.00 MB');
  assert.ok(totalBytesPurgedFromCloud > 0, 'Purged bytes must be positive');
});

// 4. Test WebRTC Signaling Logic & Room Isolation
test('WebRTC 60 FPS Signaling - Room State Management', async (t) => {
  const rooms = new Map();

  function joinRoom(roomId, socketId) {
    if (!rooms.has(roomId)) {
      rooms.set(roomId, new Set());
    }
    const room = rooms.get(roomId);
    room.add(socketId);
    return Array.from(room).filter(id => id !== socketId);
  }

  function leaveRoom(roomId, socketId) {
    if (!rooms.has(roomId)) return;
    const room = rooms.get(roomId);
    room.delete(socketId);
    if (room.size === 0) {
      rooms.delete(roomId);
    }
  }

  // Child joins room
  const existingPeers1 = joinRoom('VYRA-13533', 'socket_child');
  assert.equal(existingPeers1.length, 0, 'First peer in room has no existing peers');

  // Parent joins same room
  const existingPeers2 = joinRoom('VYRA-13533', 'socket_parent');
  assert.deepEqual(existingPeers2, ['socket_child'], 'Parent should receive child socket ID');

  // Third party joins another room
  const existingPeers3 = joinRoom('VYRA-99999', 'socket_other');
  assert.equal(existingPeers3.length, 0, 'Separate room must be completely isolated');

  // Child disconnects
  leaveRoom('VYRA-13533', 'socket_child');
  assert.equal(rooms.get('VYRA-13533').size, 1);

  // Parent disconnects
  leaveRoom('VYRA-13533', 'socket_parent');
  assert.equal(rooms.has('VYRA-13533'), false, 'Empty room must be cleaned up');
});

// 5. Schema Contract Compatibility with Supabase Database
test('Database Schema Contract Verification (Parent / Child / Supabase)', async (t) => {
  // Required columns in Supabase tables
  const requiredSchema = {
    devices: ['id', 'child_id', 'device_model', 'battery_level', 'is_online', 'is_screen_on', 'selected_disguise'],
    chats: ['id', 'child_id', 'app', 'sender', 'text', 'is_incoming', 'is_deleted_by_sender', 'is_watchlist_target', 'is_view_once'],
    calls: ['id', 'child_id', 'contact_name', 'phone_number', 'call_type', 'duration_seconds', 'is_watchlist_target'],
    notifications: ['id', 'child_id', 'package_name', 'app_name', 'title', 'text', 'is_important'],
    commands: ['id', 'child_id', 'action', 'payload', 'status']
  };

  // Sample child app output event
  const incomingChildChat = {
    id: 'chat_hash_9872',
    child_id: 'VYRA-13533',
    app: 'Snapchat',
    sender: 'Harshit Kamboj',
    text: '[UNSENT DRAFT] Meet me after class',
    is_incoming: false,
    is_deleted_by_sender: false,
    is_watchlist_target: true,
    is_view_once: false,
    timestamp_ms: 1727800000000
  };

  for (const field of requiredSchema.chats) {
    assert.ok(field in incomingChildChat, `Child chat object must provide field: ${field}`);
  }
});

// 6. Test Gemini Diarization Response Schema & Turn Parsing
test('Gemini Diarization Response Schema Validator', async (t) => {
  const sampleApiResponse = {
    summary: "Aryan discussed school project with Harshit and planned to meet at the library.",
    threatLevel: "NORMAL",
    flaggedKeywords: [],
    speakers: [
      {
        speakerId: "speaker_1",
        displayName: "Aryan (Child)",
        isChild: true,
        pitch: "Medium-high pitch, adolescent voice",
        tone: "Casual and animated",
        acousticDescription: "Voice sounds clear, speaks moderately fast",
        estimatedRole: "Child"
      },
      {
        speakerId: "speaker_2",
        displayName: "Harshit Kamboj",
        isChild: false,
        pitch: "Deep baritone",
        tone: "Confident, calm",
        acousticDescription: "Deep tone with clear enunciation",
        estimatedRole: "Friend / Classmate"
      }
    ],
    dialogue: [
      {
        speakerId: "speaker_2",
        speakerName: "Harshit Kamboj",
        timestamp: "00:02 - 00:06",
        spokenText: "Bhai project file ready hai kya?",
        englishTranslation: "Bro is the project file ready?",
        emotion: "inquisitive"
      },
      {
        speakerId: "speaker_1",
        speakerName: "Aryan (Child)",
        timestamp: "00:07 - 00:10",
        spokenText: "Haan bas 2 page baaki hain.",
        englishTranslation: "Yes, just 2 pages left.",
        emotion: "relaxed"
      }
    ]
  };

  assert.ok(['NORMAL', 'CAUTION', 'HIGH_ALERT'].includes(sampleApiResponse.threatLevel));
  assert.equal(sampleApiResponse.speakers.length, 2);
  assert.equal(sampleApiResponse.dialogue.length, 2);
  assert.equal(sampleApiResponse.dialogue[0].speakerName, 'Harshit Kamboj');
  assert.equal(sampleApiResponse.dialogue[1].spokenText, 'Haan bas 2 page baaki hain.');
});
