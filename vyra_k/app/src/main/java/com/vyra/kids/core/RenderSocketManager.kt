package com.vyra.kids.core

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonParser
import com.google.gson.reflect.TypeToken
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * RenderSocketManager — Socket.IO v4 (Engine.IO v4) client implemented directly
 * over OkHttp WebSocket. No socket.io-java dependency; APK footprint is ~0 bytes extra.
 *
 * Engine.IO packet types:
 *   0 = OPEN, 1 = CLOSE, 2 = PING, 3 = PONG, 4 = MESSAGE, 5 = UPGRADE, 6 = NOOP
 *
 * Socket.IO packet types (prefixed inside EIO MESSAGE "4"):
 *   40 = CONNECT, 41 = DISCONNECT, 42 = EVENT, 43 = ACK
 *
 * Typical handshake sequence:
 *   ← Server: 0{"sid":"...","pingInterval":25000,"pingTimeout":20000}
 *   → Client: 40                      (Socket.IO CONNECT to default namespace)
 *   ← Server: 40{"sid":"..."}         (Socket.IO CONNECT acknowledged)
 *   → Client: 42["join_room",{...}]   (join our room)
 *   ← Server: 2                       (periodic PING)
 *   → Client: 3                       (PONG reply)
 */
class RenderSocketManager private constructor(private val context: Context) {

    // ─────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────

    private val TAG = "RenderSocketManager"

    /** Milliseconds to wait between reconnect attempts (doubles each time, capped at MAX_BACKOFF_MS). */
    private val INITIAL_BACKOFF_MS = 1_000L
    private val MAX_BACKOFF_MS = 30_000L

    // ─────────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────────

    private val gson = Gson()

    /**
     * Dedicated OkHttpClient for WebSocket only — long read-timeout because
     * the connection must live indefinitely (heartbeats keep it alive).
     */
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)   // infinite — required for WebSocket
        .writeTimeout(10, TimeUnit.SECONDS)
        .pingInterval(0, TimeUnit.MILLISECONDS)  // we handle pings ourselves via EIO protocol
        .build()

    /** The live WebSocket handle; null when disconnected. */
    private val socketRef = AtomicReference<WebSocket?>(null)

    /** True once connect() has been called and disconnect() has not yet been called. */
    private val wantConnected = AtomicBoolean(false)

    /** Publicly readable connectivity flag. */
    @Volatile
    var isConnected: Boolean = false
        private set

    /** Incremented on every successful OPEN so stale listeners self-discard. */
    private val sessionToken = AtomicInteger(0)

    /** Reconnect scheduler — single-threaded so scheduling is serialised. */
    private val scheduler: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "RenderSocketManager-scheduler").apply { isDaemon = true }
        }

    /** Future for any pending reconnect task (so we can cancel it on explicit disconnect). */
    private val reconnectFuture = AtomicReference<ScheduledFuture<*>?>(null)

    /** Backoff delay for next reconnect attempt. Reset to INITIAL_BACKOFF_MS on success. */
    private val currentBackoffMs = AtomicLong(INITIAL_BACKOFF_MS)

    /** Saved connection parameters so reconnect can re-use them. */
    @Volatile private var savedChildId: String = ""
    @Volatile private var savedCallback: ((action: String, payload: Map<String, Any>) -> Unit)? = null

    /** Server-negotiated ping interval (ms). Populated from the EIO OPEN packet. */
    private val pingIntervalMs = AtomicLong(25_000L)

    /** Timer that sends our keep-alive check to detect missed pongs (uses pingTimeout). */
    private val pingTimeoutMs = AtomicLong(20_000L)

    /** Scheduled future for server-initiated ping watchdog. */
    private val pingWatchdogFuture = AtomicReference<ScheduledFuture<*>?>(null)

    // ─────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Starts the Socket.IO connection and registers [onCommandReceived] as the
     * event handler for `execute_command` and `control_camera` events.
     *
     * Safe to call multiple times; subsequent calls update the callback and
     * trigger a fresh connection attempt only if not already connected.
     *
     * @param childId          The pairing code identifying this child device (e.g. "VYRA-13533").
     *                         If blank, it is read from [PrefsManager].
     * @param onCommandReceived Invoked on the calling thread's executor whenever a command arrives.
     *                         Receives (action, payload) where action is an uppercase string such
     *                         as "START_CAMERA_STREAM", "STOP_CAMERA_STREAM", "SWITCH_CAMERA_LENS".
     */
    fun connect(
        childId: String = "",
        onCommandReceived: (action: String, payload: Map<String, Any>) -> Unit
    ) {
        val resolvedId = childId.ifBlank {
            PrefsManager.getInstance(context).pairingCode
        }.trim().uppercase()

        savedChildId = resolvedId
        savedCallback = onCommandReceived
        wantConnected.set(true)

        Log.i(TAG, "connect() called — childId=$resolvedId")
        openSocket()
    }

    /**
     * Cleanly shuts down the connection and cancels all reconnect attempts.
     * After calling disconnect(), no further callbacks will be fired.
     */
    fun disconnect() {
        Log.i(TAG, "disconnect() called — tearing down")
        wantConnected.set(false)
        cancelPingWatchdog()
        cancelReconnect()

        val ws = socketRef.getAndSet(null)
        ws?.close(1000, "Client disconnect")
        isConnected = false
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — connection lifecycle
    // ─────────────────────────────────────────────────────────────────────

    private fun openSocket() {
        if (!wantConnected.get()) return

        // Cancel any pending reconnect — we're opening now.
        cancelReconnect()

        val url = buildSocketUrl()
        Log.d(TAG, "Opening WebSocket → $url")

        val request = Request.Builder().url(url).build()
        val token = sessionToken.incrementAndGet()

        val listener = object : WebSocketListener() {

            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (sessionToken.get() != token) {
                    webSocket.close(1000, "stale")
                    return
                }
                socketRef.set(webSocket)
                Log.i(TAG, "WebSocket opened (session=$token)")
                // EIO handshake: server will immediately send "0{...}" — wait for it.
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (sessionToken.get() != token) return
                handleMessage(webSocket, text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.w(TAG, "WebSocket closing: $code $reason")
                webSocket.close(1000, "ack closing")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (sessionToken.get() != token) return
                Log.w(TAG, "WebSocket closed: $code $reason")
                onDisconnected()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (sessionToken.get() != token) return
                Log.e(TAG, "WebSocket failure: ${t.message}", t)
                onDisconnected()
            }
        }

        httpClient.newWebSocket(request, listener)
    }

    private fun onDisconnected() {
        isConnected = false
        socketRef.set(null)
        cancelPingWatchdog()
        scheduleReconnect()
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — Engine.IO / Socket.IO message parsing
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Routes an incoming raw WebSocket text frame through the Engine.IO / Socket.IO
     * protocol state machine.
     */
    private fun handleMessage(webSocket: WebSocket, raw: String) {
        if (raw.isEmpty()) return

        when (val eioType = raw[0]) {
            // ── Engine.IO OPEN ──────────────────────────────────────────
            '0' -> handleEioOpen(webSocket, raw.drop(1))

            // ── Engine.IO PING (server → client heartbeat) ─────────────
            '2' -> {
                Log.v(TAG, "EIO PING received → sending PONG")
                webSocket.send("3") // PONG
                resetPingWatchdog(webSocket)
            }

            // ── Engine.IO MESSAGE (contains Socket.IO frames) ──────────
            '4' -> {
                if (raw.length < 2) return
                handleSocketIoPacket(webSocket, raw.drop(1))
            }

            // ── Engine.IO NOOP / UPGRADE / CLOSE — ignore / handle ─────
            '1' -> {
                Log.i(TAG, "EIO CLOSE received from server")
                onDisconnected()
            }
            '6' -> Log.v(TAG, "EIO NOOP")
            else -> Log.v(TAG, "Unknown EIO packet type='$eioType': $raw")
        }
    }

    /**
     * Parses the Engine.IO OPEN payload and sends the Socket.IO CONNECT packet.
     *
     * Example payload: {"sid":"abc","upgrades":["websocket"],"pingInterval":25000,"pingTimeout":20000}
     */
    private fun handleEioOpen(webSocket: WebSocket, jsonPayload: String) {
        try {
            val map: Map<String, Any> = gson.fromJson(
                jsonPayload,
                object : TypeToken<Map<String, Any>>() {}.type
            ) ?: emptyMap()

            (map["pingInterval"] as? Double)?.toLong()?.let { pingIntervalMs.set(it) }
            (map["pingTimeout"] as? Double)?.toLong()?.let { pingTimeoutMs.set(it) }

            Log.i(TAG, "EIO OPEN — sid=${map["sid"]}, pingInterval=${pingIntervalMs.get()}ms")
        } catch (e: Exception) {
            Log.w(TAG, "Could not parse EIO OPEN payload: $jsonPayload — $e")
        }

        // Send Socket.IO CONNECT (packet "40") to the default namespace "/".
        webSocket.send("40")
        Log.d(TAG, "Sent SIO CONNECT (40)")
    }

    /**
     * Handles Socket.IO-level packets (already stripped of the leading "4" EIO prefix).
     *
     * Packet format after the EIO "4" prefix:
     *   0 → SIO CONNECT   e.g.  40{"sid":"..."}
     *   1 → SIO DISCONNECT
     *   2 → SIO EVENT     e.g.  42["event_name", {data}]
     *   3 → SIO ACK
     */
    private fun handleSocketIoPacket(webSocket: WebSocket, sioRaw: String) {
        if (sioRaw.isEmpty()) return

        when (sioRaw[0]) {
            // Socket.IO CONNECT acknowledged ─────────────────────────────
            '0' -> {
                Log.i(TAG, "SIO CONNECT ack — joined namespace")
                isConnected = true
                currentBackoffMs.set(INITIAL_BACKOFF_MS) // reset backoff on success
                resetPingWatchdog(webSocket)
                sendJoinRoom(webSocket)
            }

            // Socket.IO DISCONNECT ───────────────────────────────────────
            '1' -> {
                Log.w(TAG, "SIO DISCONNECT received")
                onDisconnected()
            }

            // Socket.IO EVENT ────────────────────────────────────────────
            '2' -> {
                val jsonArray = sioRaw.drop(1).trim()
                dispatchEvent(jsonArray)
            }

            // Socket.IO ACK — we don't use acks, ignore safely ──────────
            '3' -> Log.v(TAG, "SIO ACK received (ignored)")

            else -> Log.v(TAG, "Unknown SIO packet: $sioRaw")
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — event dispatching
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Parses a Socket.IO EVENT JSON array and dispatches known events to [savedCallback].
     *
     * EVENT frame format: ["event_name", {optional_data_object}]
     */
    private fun dispatchEvent(jsonArrayStr: String) {
        try {
            val arr: JsonArray = JsonParser.parseString(jsonArrayStr).asJsonArray
            if (arr.size() < 1) return

            val eventName = arr[0].asString
            Log.d(TAG, "SIO EVENT: $eventName")

            when (eventName) {
                // ── execute_command ──────────────────────────────────────
                "execute_command" -> {
                    val dataObj = if (arr.size() >= 2) arr[1].asJsonObject else return
                    val action = dataObj.get("action")?.asString ?: return
                    val payloadElement = dataObj.get("payload")
                    val payload: Map<String, Any> = if (payloadElement != null && payloadElement.isJsonObject) {
                        gson.fromJson(payloadElement, object : TypeToken<Map<String, Any>>() {}.type) ?: emptyMap()
                    } else {
                        emptyMap()
                    }
                    Log.i(TAG, "execute_command → action=$action payload=$payload")
                    savedCallback?.invoke(action.uppercase(), payload)
                }

                // ── control_camera ───────────────────────────────────────
                "control_camera" -> {
                    val dataObj = if (arr.size() >= 2) arr[1].asJsonObject else return
                    val action = dataObj.get("action")?.asString?.lowercase() ?: ""
                    val facing = dataObj.get("facing")?.asString ?: "back"
                    val payload: Map<String, Any> = mapOf("facing" to facing)

                    val mappedAction = when (action) {
                        "switch", "flip", "switch_lens" -> "SWITCH_CAMERA_LENS"
                        "stop"                          -> "STOP_CAMERA_STREAM"
                        else                            -> "START_CAMERA_STREAM" // "start" or any unknown action
                    }

                    Log.i(TAG, "control_camera → mapped=$mappedAction facing=$facing")
                    savedCallback?.invoke(mappedAction, payload)
                }

                // ── peer_joined / peer_disconnected ──────────────────────
                "peer_joined" -> {
                    Log.i(TAG, "Peer joined the room")
                    savedCallback?.invoke("PEER_JOINED", emptyMap())
                }
                "peer_disconnected" -> {
                    Log.i(TAG, "Peer disconnected from room")
                    savedCallback?.invoke("PEER_DISCONNECTED", emptyMap())
                }

                // ── WebRTC signalling — pass through as-is ───────────────
                "webrtc_offer", "webrtc_answer", "ice_candidate" -> {
                    val dataObj = if (arr.size() >= 2) arr[1].asJsonObject else return
                    val payload: Map<String, Any> = gson.fromJson(
                        dataObj,
                        object : TypeToken<Map<String, Any>>() {}.type
                    ) ?: emptyMap()
                    savedCallback?.invoke(eventName.uppercase(), payload)
                }

                else -> Log.v(TAG, "Unhandled SIO event: $eventName")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error dispatching SIO event: $jsonArrayStr", e)
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — outbound helpers
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Emits the Socket.IO `join_room` event so the child device is placed
     * in the room that the parent dashboard is watching.
     *
     * Frame: 42["join_room",{"role":"child","childId":"VYRA-13533"}]
     */
    private fun sendJoinRoom(webSocket: WebSocket) {
        val childId = savedChildId.ifBlank {
            PrefsManager.getInstance(context).pairingCode.trim().uppercase()
        }
        val payloadJson = gson.toJson(mapOf("role" to "child", "childId" to childId))
        val frame = """42["join_room",$payloadJson]"""
        webSocket.send(frame)
        Log.i(TAG, "Sent join_room — childId=$childId")
    }

    /**
     * Emits any Socket.IO event over the current WebSocket.
     * Silently drops the emission if the socket is not connected.
     */
    fun emit(eventName: String, data: Map<String, Any>) {
        val ws = socketRef.get() ?: run {
            Log.w(TAG, "emit($eventName) dropped — not connected")
            return
        }
        val payloadJson = gson.toJson(data)
        val frame = """42["$eventName",$payloadJson]"""
        ws.send(frame)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — heartbeat / ping-watchdog
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Schedules a watchdog that fires after (pingInterval + pingTimeout) ms.
     * If the server hasn't pinged us by then we assume the connection is dead
     * and tear down for reconnection.
     *
     * Re-arms itself each time we receive a PING from the server.
     */
    private fun resetPingWatchdog(webSocket: WebSocket) {
        cancelPingWatchdog()
        val deadline = pingIntervalMs.get() + pingTimeoutMs.get()
        val future = scheduler.schedule({
            Log.w(TAG, "Ping watchdog fired — no PING received in ${deadline}ms, reconnecting")
            webSocket.cancel()       // hard kill; onFailure will trigger reconnect
        }, deadline, TimeUnit.MILLISECONDS)
        pingWatchdogFuture.set(future)
    }

    private fun cancelPingWatchdog() {
        pingWatchdogFuture.getAndSet(null)?.cancel(false)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — auto-reconnect with exponential backoff
    // ─────────────────────────────────────────────────────────────────────

    private fun scheduleReconnect() {
        if (!wantConnected.get()) return

        val delay = currentBackoffMs.get()
        // Advance backoff (doubles, capped at MAX_BACKOFF_MS) for the next attempt.
        currentBackoffMs.set(minOf(delay * 2, MAX_BACKOFF_MS))

        Log.i(TAG, "Scheduling reconnect in ${delay}ms (next backoff=${currentBackoffMs.get()}ms)")

        val future = scheduler.schedule({
            if (wantConnected.get()) {
                Log.i(TAG, "Reconnect attempt — opening socket")
                openSocket()
            }
        }, delay, TimeUnit.MILLISECONDS)
        reconnectFuture.set(future)
    }

    private fun cancelReconnect() {
        reconnectFuture.getAndSet(null)?.cancel(false)
    }

    // ─────────────────────────────────────────────────────────────────────
    // Internal — URL builder
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Builds the Engine.IO v4 WebSocket upgrade URL.
     *
     * GET https://vyra-backend.onrender.com/socket.io/?EIO=4&transport=websocket
     * The protocol is automatically upgraded from HTTPS→WSS by OkHttp.
     */
    private fun buildSocketUrl(): String {
        val base = AppConstants.WEBSOCKET_SIGNALLING_URL
            .trimEnd('/')
            .replace("https://", "wss://")
            .replace("http://", "ws://")
        return "$base/socket.io/?EIO=4&transport=websocket"
    }

    // ─────────────────────────────────────────────────────────────────────
    // Singleton
    // ─────────────────────────────────────────────────────────────────────

    companion object {
        @Volatile
        private var instance: RenderSocketManager? = null

        fun getInstance(context: Context): RenderSocketManager {
            return instance ?: synchronized(this) {
                instance ?: RenderSocketManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
