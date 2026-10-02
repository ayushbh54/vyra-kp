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
     * Polls pending remote commands sent by parent via Supabase commands table
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
