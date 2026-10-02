package com.vyra.kids.core

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * REST-based client for Supabase PostgreSQL database.
 * Allows child device to dual-sync or migrate to Supabase without requiring heavy SDKs.
 */
class SupabaseSyncManager private constructor(private val context: Context) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
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

    fun syncRecord(table: String, payload: Map<String, Any>) {
        if (supabaseUrl.contains("placeholder") || anonKey.contains("placeholder")) {
            // Not configured yet
            return
        }

        scope.launch {
            try {
                val json = gson.toJson(payload)
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
}
