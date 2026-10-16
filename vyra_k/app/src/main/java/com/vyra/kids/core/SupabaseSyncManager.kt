package com.vyra.kids.core

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * REST-based client for Supabase PostgreSQL database and Storage buckets.
 * Allows child device to sync telemetry, chats, calls, notifications, and media files
 * completely independent of Firebase with zero background Play Services dependencies.
 */
class SupabaseSyncManager private constructor(private val context: Context) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO)

    companion object {
        @Volatile
        private var instance: SupabaseSyncManager? = null

        fun getInstance(context: Context): SupabaseSyncManager {
            return instance ?: synchronized(this) {
                instance ?: SupabaseSyncManager(context.applicationContext).also { instance = it }
            }
        }
    }

    private val supabaseUrl: String
        get() = AppConstants.SUPABASE_URL

    private val anonKey: String
        get() = AppConstants.SUPABASE_ANON_KEY

    val isConfigured: Boolean
        get() = !supabaseUrl.contains("placeholder") &&
                !anonKey.contains("placeholder") &&
                supabaseUrl.isNotBlank() &&
                anonKey.isNotBlank()

    /**
     * Converts camelCase map to snake_case map matching Supabase SQL tables
     */
    private fun toSnakeCaseMap(map: Map<String, Any>): Map<String, Any> {
        val result = mutableMapOf<String, Any>()
        for ((key, value) in map) {
            val snakeKey = key.replace(Regex("([a-z])([A-Z])"), "$1_$2").lowercase()
            result[snakeKey] = value
        }
        return result
    }

    /**
     * Inserts or upserts a record into a Supabase PostgreSQL table
     */
    fun syncRecord(table: String, payload: Map<String, Any>) {
        if (!isConfigured) return

        scope.launch {
            try {
                val formattedPayload = toSnakeCaseMap(payload)
                val json = gson.toJson(formattedPayload)
                val body = json.toRequestBody("application/json; charset=utf-8".toMediaType())
                val request = Request.Builder()
                    .url("$supabaseUrl/rest/v1/$table")
                    .addHeader("apikey", anonKey)
                    .addHeader("Authorization", "Bearer $anonKey")
                    .addHeader("Prefer", "resolution=merge-duplicates")
                    .post(body)
                    .build()

                val response = client.newCall(request).execute()
                if (!response.isSuccessful) {
                    Log.w(AppConstants.TAG, "Supabase sync to $table failed: HTTP ${response.code}")
                }
                response.close()
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error syncing to Supabase table $table", e)
            }
        }
    }

    /**
     * Uploads media file (audio recording or snap photo) to Supabase Storage bucket.
     * Returns the publicly accessible download URL on success.
     */
    fun uploadFile(
        bucket: String,
        path: String,
        file: File,
        mimeType: String = "application/octet-stream",
        onComplete: ((String?) -> Unit)? = null
    ) {
        if (!isConfigured || !file.exists()) {
            onComplete?.invoke(null)
            return
        }

        scope.launch {
            try {
                val body = file.asRequestBody(mimeType.toMediaType())
                val request = Request.Builder()
                    .url("$supabaseUrl/storage/v1/object/$bucket/$path")
                    .addHeader("apikey", anonKey)
                    .addHeader("Authorization", "Bearer $anonKey")
                    .addHeader("x-upsert", "true")
                    .post(body)
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    val publicUrl = "$supabaseUrl/storage/v1/object/public/$bucket/$path"
                    Log.i(AppConstants.TAG, "Supabase Storage: Uploaded $path to $bucket successfully: $publicUrl")
                    onComplete?.invoke(publicUrl)
                } else {
                    Log.w(AppConstants.TAG, "Supabase Storage: Upload $path failed: HTTP ${response.code}")
                    onComplete?.invoke(null)
                }
                response.close()
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Supabase Storage: Error uploading $path", e)
                onComplete?.invoke(null)
            }
        }
    }

    /**
     * Polls pending remote commands sent by parent via Supabase commands table.
     * Used as FALLBACK when WebSocket is unavailable.
     * Primary path: subscribeToCommands() WebSocket listener.
     */
    fun pollPendingCommands(childId: String, onCommandReceived: (action: String, payload: Map<String, Any>) -> Unit) {
        if (!isConfigured) return

        scope.launch {
            try {
                val request = Request.Builder()
                    .url("$supabaseUrl/rest/v1/commands?child_id=eq.$childId&status=eq.PENDING&select=*")
                    .addHeader("apikey", anonKey)
                    .addHeader("Authorization", "Bearer $anonKey")
                    .get()
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    val bodyStr = response.body?.string() ?: ""
                    val type = object : TypeToken<List<Map<String, Any>>>() {}.type
                    val commands: List<Map<String, Any>> = gson.fromJson(bodyStr, type) ?: emptyList()
                    for (cmd in commands) {
                        val cmdId = cmd["id"]?.toString() ?: continue
                        val action = cmd["action"]?.toString() ?: continue
                        @Suppress("UNCHECKED_CAST")
                        val payload = cmd["payload"] as? Map<String, Any> ?: emptyMap()
                        markCommandExecuted(cmdId)
                        onCommandReceived(action, payload)
                    }
                }
                response.close()
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error polling Supabase commands", e)
            }
        }
    }

    // ─────────────────── Supabase Realtime WebSocket (instant commands) ──────────

    /**
     * Opens a Supabase Realtime channel subscription on the commands table.
     * Any INSERT of a PENDING command for this childId is instantly delivered.
     * Replaces 30-second polling with <200ms delivery.
     *
     * Supabase Realtime protocol:
     *   1. WS connect to $supabaseUrl/realtime/v1/websocket?apikey=...&vsn=1.0.0
     *   2. Send phx_join to channel "realtime:public:commands:child_id=eq.$childId"
     *   3. Receive phx_reply with postgres_changes events on INSERT
     */
    @Volatile private var realtimeWebSocket: okhttp3.WebSocket? = null
    @Volatile private var isRealtimeConnected = false

    fun subscribeToCommands(childId: String, onCommandReceived: (action: String, payload: Map<String, Any>) -> Unit) {
        if (!isConfigured) return
        disconnectRealtime()

        val wsUrl = supabaseUrl
            .replace("https://", "wss://")
            .replace("http://", "ws://") +
            "/realtime/v1/websocket?apikey=$anonKey&vsn=1.0.0"

        val request = okhttp3.Request.Builder().url(wsUrl).build()

        val listener = object : okhttp3.WebSocketListener() {
            private var heartbeatRef = 0

            override fun onOpen(ws: okhttp3.WebSocket, response: okhttp3.Response) {
                isRealtimeConnected = true
                Log.i(AppConstants.TAG, "Supabase Realtime: WebSocket connected")

                // Join channel for commands table filtered by child_id
                val joinMsg = """{"topic":"realtime:public:commands","event":"phx_join","payload":{"config":{"broadcast":{"self":false},"presence":{"key":""},"postgres_changes":[{"event":"INSERT","schema":"public","table":"commands","filter":"child_id=eq.$childId"}]}},"ref":"1"}"""
                ws.send(joinMsg)
                Log.i(AppConstants.TAG, "Supabase Realtime: Joined commands channel for $childId")

                // Heartbeat every 30s to keep connection alive
                scope.launch {
                    while (isRealtimeConnected) {
                        kotlinx.coroutines.delay(30_000)
                        if (!isRealtimeConnected) break
                        heartbeatRef++
                        ws.send("""{"topic":"phoenix","event":"heartbeat","payload":{},"ref":"hb_$heartbeatRef"}""")
                    }
                }
            }

            override fun onMessage(ws: okhttp3.WebSocket, text: String) {
                try {
                    @Suppress("UNCHECKED_CAST")
                    val envelope = gson.fromJson(text, Map::class.java) as? Map<String, Any> ?: return
                    val event = envelope["event"]?.toString() ?: return

                    if (event == "postgres_changes") {
                        @Suppress("UNCHECKED_CAST")
                        val payloadMap = envelope["payload"] as? Map<String, Any> ?: return
                        @Suppress("UNCHECKED_CAST")
                        val record = payloadMap["record"] as? Map<String, Any> ?: return

                        val cmdId = record["id"]?.toString() ?: return
                        val status = record["status"]?.toString() ?: ""
                        val action = record["action"]?.toString() ?: return
                        if (status != "PENDING") return

                        @Suppress("UNCHECKED_CAST")
                        val cmdPayload = record["payload"] as? Map<String, Any> ?: emptyMap()

                        Log.i(AppConstants.TAG, "Supabase Realtime: Received command [$action] instantly!")
                        markCommandExecuted(cmdId)
                        onCommandReceived(action, cmdPayload)
                    }
                } catch (e: Exception) {
                    Log.w(AppConstants.TAG, "Supabase Realtime: message parse error", e)
                }
            }

            override fun onFailure(ws: okhttp3.WebSocket, t: Throwable, response: okhttp3.Response?) {
                isRealtimeConnected = false
                Log.w(AppConstants.TAG, "Supabase Realtime: disconnected — ${t.message}. Reconnecting in 15s...")
                // Auto-reconnect after 15s
                scope.launch {
                    kotlinx.coroutines.delay(15_000)
                    if (!isRealtimeConnected) {
                        subscribeToCommands(childId, onCommandReceived)
                    }
                }
            }

            override fun onClosed(ws: okhttp3.WebSocket, code: Int, reason: String) {
                isRealtimeConnected = false
                Log.i(AppConstants.TAG, "Supabase Realtime: closed ($code: $reason)")
            }
        }

        realtimeWebSocket = client.newWebSocket(request, listener)
    }

    fun disconnectRealtime() {
        isRealtimeConnected = false
        realtimeWebSocket?.close(1000, "Shutting down")
        realtimeWebSocket = null
    }

    private fun markCommandExecuted(cmdId: String) {
        scope.launch {
            try {
                val updateBody = gson.toJson(mapOf("status" to "EXECUTED"))
                    .toRequestBody("application/json; charset=utf-8".toMediaType())
                val patchRequest = Request.Builder()
                    .url("$supabaseUrl/rest/v1/commands?id=eq.$cmdId")
                    .addHeader("apikey", anonKey)
                    .addHeader("Authorization", "Bearer $anonKey")
                    .patch(updateBody)
                    .build()
                client.newCall(patchRequest).execute().close()
            } catch (_: Exception) {}
        }
    }
}

