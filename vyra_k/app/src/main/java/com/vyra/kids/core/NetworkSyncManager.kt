package com.vyra.kids.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import androidx.work.*
import com.google.gson.Gson
import com.vyra.kids.workers.VaultSyncWorker
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

class NetworkSyncManager private constructor(private val context: Context) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()

    companion object {
        @Volatile
        private var instance: NetworkSyncManager? = null

        fun getInstance(context: Context): NetworkSyncManager {
            return instance ?: synchronized(this) {
                instance ?: NetworkSyncManager(context.applicationContext).also { instance = it }
            }
        }
    }

    fun isOnline(): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val activeNetwork = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    fun syncData(endpoint: String, payload: Map<String, Any>, onComplete: ((Boolean) -> Unit)? = null) {
        if (!isOnline()) {
            // Save payload to offline queue
            saveToOfflineQueue(endpoint, payload)
            scheduleOfflineSyncWorker()
            onComplete?.invoke(false)
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val json = gson.toJson(payload)
                val body = json.toRequestBody("application/json; charset=utf-8".toMediaType())
                val request = Request.Builder()
                    .url("${AppConstants.BASE_SYNC_URL}/$endpoint")
                    .post(body)
                    .build()

                val response = client.newCall(request).execute()
                val success = response.isSuccessful
                response.close()
                onComplete?.invoke(success)
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Sync failed for $endpoint, storing offline", e)
                saveToOfflineQueue(endpoint, payload)
                scheduleOfflineSyncWorker()
                onComplete?.invoke(false)
            }
        }
    }

    private fun saveToOfflineQueue(endpoint: String, payload: Map<String, Any>) {
        try {
            val queueDir = File(context.filesDir, "offline_queue")
            if (!queueDir.exists()) queueDir.mkdirs()

            val fileName = "${System.currentTimeMillis()}_$endpoint.json"
            val file = File(queueDir, fileName)
            file.writeText(gson.toJson(payload))
            Log.d(AppConstants.TAG, "Saved offline item: $fileName")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Failed to write to offline queue", e)
        }
    }

    fun scheduleOfflineSyncWorker() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val syncRequest = OneTimeWorkRequestBuilder<VaultSyncWorker>()
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            "vyra_offline_sync",
            ExistingWorkPolicy.KEEP,
            syncRequest
        )
    }
}
