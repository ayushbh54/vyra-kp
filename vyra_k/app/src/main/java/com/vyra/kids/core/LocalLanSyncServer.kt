package com.vyra.kids.core

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.google.gson.Gson
import com.vyra.kids.services.LiveAudioStreamService
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStream
import java.net.*

/**
 * Lightweight Local LAN Sync Server + Live MJPEG Camera + Live WAV Audio streaming.
 *
 * HTTP Endpoints:
 *   GET /api/ping            → JSON health check
 *   GET /api/sync            → Full rolling data dump
 *   GET /api/status          → Device status
 *   GET /api/chats           → Chat messages
 *   GET /api/calls           → Call records
 *   GET /api/notifications   → Notifications
 *   GET /api/stream          → SSE push stream (real-time events)
 *   GET /api/camera-frame    → Single JPEG snapshot (one-shot, ~15ms)
 *   GET /api/camera-mjpeg    → Live MJPEG stream (multipart/x-mixed-replace)
 *   GET /api/live-audio      → Live WAV stream (audio/wav, streaming PCM)
 *   POST /api/command        → Remote command dispatch from parent
 */
class LocalLanSyncServer private constructor(private val context: Context) {

    private val gson = Gson()
    private var isRunning = false
    private var serverSocket: ServerSocket? = null
    private var udpSocket: DatagramSocket? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeStreamClients = java.util.Collections.synchronizedList(mutableListOf<Socket>())

    companion object {
        const val HTTP_PORT = 8899
        const val UDP_DISCOVERY_PORT = 8898

        @Volatile
        private var instance: LocalLanSyncServer? = null

        fun getInstance(context: Context): LocalLanSyncServer {
            return instance ?: synchronized(this) {
                instance ?: LocalLanSyncServer(context.applicationContext).also { instance = it }
            }
        }

        // MJPEG boundary string
        private const val MJPEG_BOUNDARY = "vyraframe"
    }

    fun broadcastLiveEvent(eventType: String, data: Map<String, Any>) {
        if (activeStreamClients.isEmpty()) return
        scope.launch {
            try {
                val payload = gson.toJson(mapOf(
                    "type" to eventType,
                    "data" to data,
                    "timestamp" to System.currentTimeMillis()
                ))
                val msg = "data: $payload\n\n".toByteArray(Charsets.UTF_8)
                synchronized(activeStreamClients) {
                    val iterator = activeStreamClients.iterator()
                    while (iterator.hasNext()) {
                        val client = iterator.next()
                        try {
                            client.getOutputStream().write(msg)
                            client.getOutputStream().flush()
                        } catch (e: Exception) {
                            iterator.remove()
                            try { client.close() } catch (_: Exception) {}
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(AppConstants.TAG, "Error broadcasting live event", e)
            }
        }
    }

    private val pairingCode: String
        get() = PrefsManager.getInstance(context).pairingCode.ifEmpty { "VYRA-13533" }

    private var multicastLock: WifiManager.MulticastLock? = null

    @Synchronized
    fun start() {
        if (isRunning) return
        isRunning = true
        Log.i(AppConstants.TAG, "LAN Sync Server starting on port $HTTP_PORT …")
        scope.launch { startHttpServer() }
        scope.launch { startUdpDiscoveryListener() }
        // Register LAN IP with Render backend for remote-network streaming proxy
        scope.launch { registerWithRenderBackend() }
    }

    /**
     * Registers child's current LAN IP with Render backend.
     * Enables parent to stream camera/audio even when NOT on the same WiFi.
     * Called on start + every 4 minutes to keep registration fresh.
     */
    private suspend fun registerWithRenderBackend() {
        kotlinx.coroutines.delay(3000) // wait for network to settle
        val client = okhttp3.OkHttpClient.Builder()
            .connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
            .build()
        val gson = com.google.gson.Gson()
        while (isRunning) {
            try {
                val localIp = getLocalIpAddress()
                val body = gson.toJson(mapOf(
                    "childId" to pairingCode,
                    "lanIp" to localIp,
                    "lanPort" to HTTP_PORT
                )).toByteArray(Charsets.UTF_8)
                val mediaType = "application/json; charset=utf-8".toMediaType()
                val request = okhttp3.Request.Builder()
                    .url("${AppConstants.RENDER_BACKEND_URL}/api/stream/register")
                    .post(body.toRequestBody(mediaType))
                    .build()
                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    Log.i(AppConstants.TAG, "Render: Registered LAN IP $localIp for remote streaming")
                } else {
                    Log.w(AppConstants.TAG, "Render: Registration returned ${response.code}")
                }
                response.close()
            } catch (e: Exception) {
                Log.w(AppConstants.TAG, "Render: IP registration failed — ${e.message}")
            }
            kotlinx.coroutines.delay(4 * 60 * 1000L) // refresh every 4 minutes
        }
    }



    @Synchronized
    fun stop() {
        isRunning = false
        try { if (multicastLock?.isHeld == true) multicastLock?.release() } catch (_: Exception) {}
        try { serverSocket?.close(); udpSocket?.close() } catch (_: Exception) {}
        scope.cancel()
        Log.i(AppConstants.TAG, "LAN Sync Server stopped")
    }

    // ──────────────────────────────── HTTP Server ────────────────────────────────

    private fun startHttpServer() {
        try {
            serverSocket = ServerSocket(HTTP_PORT)
            while (isRunning) {
                try {
                    val client = serverSocket?.accept() ?: continue
                    scope.launch { handleClientRequest(client) }
                } catch (e: Exception) {
                    if (!isRunning) break
                }
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "HTTP server error", e)
        }
    }

    private suspend fun handleClientRequest(client: Socket) {
        try {
            client.soTimeout = 10000
            val reader = BufferedReader(InputStreamReader(client.getInputStream()))
            val firstLine = reader.readLine() ?: return
            val parts = firstLine.split(" ")
            if (parts.size < 2) return

            val uri = parts[1]

            // ── Live MJPEG camera stream ──────────────────────────────────────────
            if (uri.startsWith("/api/camera-mjpeg")) {
                client.soTimeout = 0
                streamMjpeg(client)
                return
            }

            // ── Live WAV audio stream ─────────────────────────────────────────────
            if (uri.startsWith("/api/live-audio")) {
                client.soTimeout = 0
                streamLiveAudio(client)
                return
            }

            // ── SSE real-time event stream ────────────────────────────────────────
            if (uri.startsWith("/api/stream")) {
                client.soTimeout = 0
                val os = client.getOutputStream()
                val sseHeader = "HTTP/1.1 200 OK\r\n" +
                        "Content-Type: text/event-stream; charset=utf-8\r\n" +
                        "Cache-Control: no-cache\r\n" +
                        "Connection: keep-alive\r\n" +
                        "Access-Control-Allow-Origin: *\r\n\r\n"
                os.write(sseHeader.toByteArray(Charsets.UTF_8))
                val handshake = "data: " + gson.toJson(
                    mapOf("type" to "connected", "code" to pairingCode, "device" to android.os.Build.MODEL)
                ) + "\n\n"
                os.write(handshake.toByteArray(Charsets.UTF_8))
                os.flush()
                activeStreamClients.add(client)
                Log.i(AppConstants.TAG, "SSE client connected: ${client.inetAddress.hostAddress}")
                try {
                    while (isRunning && !client.isClosed) {
                        delay(15000)
                        try { os.write(": keepalive\n\n".toByteArray(Charsets.UTF_8)); os.flush() }
                        catch (_: Exception) { break }
                    }
                } finally {
                    activeStreamClients.remove(client)
                    try { client.close() } catch (_: Exception) {}
                }
                return
            }

            // ── REST endpoints ────────────────────────────────────────────────────
            val localData = LocalDataManager.getInstance(context)
            val statusCode: Int
            val responseBody: String

            when {
                uri.startsWith("/api/ping") -> {
                    statusCode = 200
                    responseBody = gson.toJson(mapOf(
                        "status" to "ok",
                        "code" to pairingCode,
                        "device" to android.os.Build.MODEL,
                        "cameraActive" to CameraFrameBuffer.isActive,
                        "audioActive" to AudioChunkBuffer.isActive
                    ))
                }
                uri.startsWith("/api/sync") -> {
                    statusCode = 200; responseBody = gson.toJson(localData.getAllData())
                }
                uri.startsWith("/api/status") -> {
                    statusCode = 200; responseBody = gson.toJson(localData.getStatus())
                }
                uri.startsWith("/api/chats") -> {
                    statusCode = 200; responseBody = gson.toJson(localData.getChats())
                }
                uri.startsWith("/api/calls") -> {
                    statusCode = 200; responseBody = gson.toJson(localData.getCalls())
                }
                uri.startsWith("/api/notifications") -> {
                    statusCode = 200; responseBody = gson.toJson(localData.getNotifications())
                }
                // Single JPEG snapshot — parent polls this at ~10 FPS for camera feed
                uri.startsWith("/api/camera-frame") -> {
                    val frame = CameraFrameBuffer.getFrame()
                    if (frame != null) {
                        writeJpegResponse(client, frame)
                        return
                    } else {
                        statusCode = 503
                        responseBody = "{\"error\":\"Camera not active. Send START_CAMERA command first.\"}"
                    }
                }
                else -> {
                    statusCode = 404; responseBody = "{\"error\":\"Not Found\"}"
                }
            }

            writeJsonResponse(client, statusCode, responseBody)
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "LAN client error", e)
        }
    }

    // ──────────────────────── Live MJPEG Camera Stream ───────────────────────────

    /**
     * Serves a continuous multipart/x-mixed-replace MJPEG stream.
     * Parent uses Image.memory() updated per frame — like a WhatsApp video call feed.
     * Frame rate: ~10–15 FPS depending on Camera2 capture speed + network bandwidth.
     */
    private suspend fun streamMjpeg(client: Socket) {
        val os = client.getOutputStream()
        try {
            val header = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: multipart/x-mixed-replace; boundary=$MJPEG_BOUNDARY\r\n" +
                    "Cache-Control: no-cache, no-store, must-revalidate\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Connection: keep-alive\r\n\r\n"
            os.write(header.toByteArray(Charsets.UTF_8))
            os.flush()

            Log.i(AppConstants.TAG, "MJPEG stream started for ${client.inetAddress.hostAddress}")

            var lastFrameTs = 0L
            while (isRunning && !client.isClosed) {
                val frame = CameraFrameBuffer.getFrame()
                if (frame != null && CameraFrameBuffer.lastFrameTimestampMs > lastFrameTs) {
                    lastFrameTs = CameraFrameBuffer.lastFrameTimestampMs
                    try {
                        val partHeader = "--$MJPEG_BOUNDARY\r\n" +
                                "Content-Type: image/jpeg\r\n" +
                                "Content-Length: ${frame.size}\r\n\r\n"
                        os.write(partHeader.toByteArray(Charsets.UTF_8))
                        os.write(frame)
                        os.write("\r\n".toByteArray(Charsets.UTF_8))
                        os.flush()
                    } catch (e: Exception) {
                        break   // client disconnected
                    }
                } else {
                    delay(33)   // ~30 FPS polling of the frame buffer
                }
            }
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "MJPEG stream ended: ${e.message}")
        } finally {
            try { client.close() } catch (_: Exception) {}
            Log.i(AppConstants.TAG, "MJPEG stream closed")
        }
    }

    // ──────────────────────────── Live WAV Audio Stream ──────────────────────────

    /**
     * Streams a continuous WAV-over-HTTP audio response.
     * Writes a valid WAV header with 0x7FFFFFFF data size (streaming mode),
     * then continuously writes PCM chunks from AudioChunkBuffer.
     * Parent's audioplayers plays the URL → live listen, ~200ms latency.
     */
    private suspend fun streamLiveAudio(client: Socket) {
        val os = client.getOutputStream()
        try {
            val httpHeader = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: audio/wav\r\n" +
                    "Cache-Control: no-cache\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Connection: keep-alive\r\n\r\n"
            os.write(httpHeader.toByteArray(Charsets.UTF_8))

            // Write WAV header in streaming mode (sizes = 0x7FFFFFFF = unknown/max)
            os.write(buildWavStreamHeader(
                sampleRate = LiveAudioStreamService.SAMPLE_RATE,
                channels = 1,
                bitsPerSample = 16
            ))
            os.flush()

            Log.i(AppConstants.TAG, "Live WAV audio stream started for ${client.inetAddress.hostAddress}")

            while (isRunning && !client.isClosed) {
                val chunk = AudioChunkBuffer.poll(250L)
                if (chunk != null) {
                    try {
                        os.write(chunk)
                        os.flush()
                    } catch (e: Exception) {
                        break   // client disconnected
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "Live audio stream ended: ${e.message}")
        } finally {
            try { client.close() } catch (_: Exception) {}
            Log.i(AppConstants.TAG, "Live audio stream closed")
        }
    }

    /**
     * Builds a 44-byte WAV header suitable for streaming (unknown total length).
     * Uses 0x7FFFFFFF for both RIFF chunk size and data chunk size.
     */
    private fun buildWavStreamHeader(sampleRate: Int, channels: Int, bitsPerSample: Int): ByteArray {
        val h = ByteArray(44)

        fun putInt(offset: Int, v: Int) {
            h[offset]   = (v and 0xFF).toByte()
            h[offset+1] = ((v shr 8) and 0xFF).toByte()
            h[offset+2] = ((v shr 16) and 0xFF).toByte()
            h[offset+3] = ((v shr 24) and 0xFF).toByte()
        }
        fun putShort(offset: Int, v: Int) {
            h[offset]   = (v and 0xFF).toByte()
            h[offset+1] = ((v shr 8) and 0xFF).toByte()
        }

        // RIFF chunk
        h[0]='R'.code.toByte(); h[1]='I'.code.toByte(); h[2]='F'.code.toByte(); h[3]='F'.code.toByte()
        putInt(4, 0x7FFFFFFF)   // streaming: unknown total size
        h[8]='W'.code.toByte(); h[9]='A'.code.toByte(); h[10]='V'.code.toByte(); h[11]='E'.code.toByte()

        // fmt sub-chunk
        h[12]='f'.code.toByte(); h[13]='m'.code.toByte(); h[14]='t'.code.toByte(); h[15]=' '.code.toByte()
        putInt(16, 16)           // PCM fmt size
        putShort(20, 1)          // PCM = 1
        putShort(22, channels)
        putInt(24, sampleRate)
        putInt(28, sampleRate * channels * bitsPerSample / 8)  // byte rate
        putShort(32, channels * bitsPerSample / 8)             // block align
        putShort(34, bitsPerSample)

        // data sub-chunk
        h[36]='d'.code.toByte(); h[37]='a'.code.toByte(); h[38]='t'.code.toByte(); h[39]='a'.code.toByte()
        putInt(40, 0x7FFFFFFF)   // streaming: unknown data size

        return h
    }

    // ─────────────────────── HTTP Response Helpers ───────────────────────────────

    private fun writeJpegResponse(client: Socket, jpegBytes: ByteArray) {
        try {
            val os = client.getOutputStream()
            val header = "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: image/jpeg\r\n" +
                    "Content-Length: ${jpegBytes.size}\r\n" +
                    "Cache-Control: no-cache\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Connection: close\r\n\r\n"
            os.write(header.toByteArray(Charsets.UTF_8))
            os.write(jpegBytes)
            os.flush()
            client.close()
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "writeJpegResponse error", e)
        }
    }

    private fun writeJsonResponse(client: Socket, statusCode: Int, body: String) {
        try {
            val bodyBytes = body.toByteArray(Charsets.UTF_8)
            val os: OutputStream = client.getOutputStream()
            val header = "HTTP/1.1 $statusCode OK\r\n" +
                    "Content-Type: application/json; charset=utf-8\r\n" +
                    "Content-Length: ${bodyBytes.size}\r\n" +
                    "Access-Control-Allow-Origin: *\r\n" +
                    "Connection: close\r\n\r\n"
            os.write(header.toByteArray(Charsets.UTF_8))
            os.write(bodyBytes)
            os.flush()
            client.close()
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "writeJsonResponse error", e)
        }
    }

    // ────────────────────────── UDP Discovery ────────────────────────────────────

    private fun startUdpDiscoveryListener() {
        try {
            udpSocket = DatagramSocket(UDP_DISCOVERY_PORT)
            val buffer = ByteArray(1024)
            while (isRunning) {
                val packet = DatagramPacket(buffer, buffer.size)
                udpSocket?.receive(packet)
                val message = String(packet.data, 0, packet.length).trim()
                if (message.contains("VYRA_DISCOVER") || message.contains(pairingCode)) {
                    val localIp = getLocalIpAddress()
                    val reply = gson.toJson(mapOf(
                        "type" to "VYRA_ANNOUNCE",
                        "code" to pairingCode,
                        "ip" to localIp,
                        "port" to HTTP_PORT,
                        "model" to android.os.Build.MODEL
                    ))
                    val replyBytes = reply.toByteArray(Charsets.UTF_8)
                    udpSocket?.send(DatagramPacket(replyBytes, replyBytes.size, packet.address, packet.port))
                    Log.d(AppConstants.TAG, "Responded to LAN discovery from ${packet.address.hostAddress}")
                }
            }
        } catch (e: Exception) {
            if (isRunning) Log.e(AppConstants.TAG, "UDP discovery error", e)
        }
    }

    fun getLocalIpAddress(): String {
        try {
            val interfaces = java.util.Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                val addrs = java.util.Collections.list(intf.inetAddresses)
                for (addr in addrs) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address)
                        return addr.hostAddress ?: "127.0.0.1"
                }
            }
        } catch (_: Exception) {}
        return "127.0.0.1"
    }
}
