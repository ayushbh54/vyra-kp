package com.vyra.kids.workers

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.google.gson.Gson
import com.vyra.kids.core.AppConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

class VaultSyncWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val gson = Gson()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        Log.i(AppConstants.TAG, "VaultSyncWorker activated: Uploading queued offline recordings and events")

        var allSucceeded = true

        // 1. Sync offline audio recordings from hidden vault
        val vaultDir = File(context.filesDir, AppConstants.BACKUP_VAULT_FOLDER)
        if (vaultDir.exists() && vaultDir.isDirectory) {
            val files = vaultDir.listFiles() ?: emptyArray()
            for (file in files) {
                if (file.isFile && file.length() > 0) {
                    val uploaded = uploadVaultFile(file)
                    if (uploaded) {
                        Log.i(AppConstants.TAG, "Vault file uploaded and removed from local storage: ${file.name}")
                        file.delete()
                    } else {
                        allSucceeded = false
                    }
                }
            }
        }

        // 2. Sync queued JSON events (Chats, SMS, Notifications)
        val queueDir = File(context.filesDir, "offline_queue")
        if (queueDir.exists() && queueDir.isDirectory) {
            val jsonFiles = queueDir.listFiles() ?: emptyArray()
            for (jsonFile in jsonFiles) {
                if (jsonFile.isFile && jsonFile.name.endsWith(".json")) {
                    val uploaded = uploadJsonEvent(jsonFile)
                    if (uploaded) {
                        jsonFile.delete()
                    } else {
                        allSucceeded = false
                    }
                }
            }
        }

        if (allSucceeded) Result.success() else Result.retry()
    }

    private fun uploadVaultFile(file: File): Boolean {
        return try {
            val supabase = com.vyra.kids.core.SupabaseSyncManager.getInstance(context)
            if (supabase.isConfigured) {
                val childId = com.vyra.kids.core.PrefsManager.getInstance(context).pairingCode.ifEmpty { "child_1" }
                supabase.uploadFile("recordings", "$childId/${file.name}", file, "audio/mp4")
            }

            val mediaType = "audio/*".toMediaType()
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("fileName", file.name)
                .addFormDataPart("recording", file.name, file.asRequestBody(mediaType))
                .addFormDataPart("file", file.name, file.asRequestBody(mediaType))
                .build()

            val request = Request.Builder()
                .url("${AppConstants.BASE_SYNC_URL}/recordings/upload")
                .post(requestBody)
                .build()

            val response = client.newCall(request).execute()
            val success = response.isSuccessful
            response.close()
            success || supabase.isConfigured
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Failed uploading vault file: ${file.name}", e)
            false
        }
    }

    private fun uploadJsonEvent(jsonFile: File): Boolean {
        return try {
            val content = jsonFile.readText()
            val endpoint = jsonFile.name.substringAfter("_").substringBefore(".json")

            val body = content.toRequestBody("application/json; charset=utf-8".toMediaType())
            val request = Request.Builder()
                .url("${AppConstants.BASE_SYNC_URL}/$endpoint")
                .post(body)
                .build()

            val response = client.newCall(request).execute()
            val success = response.isSuccessful
            response.close()
            success
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Failed uploading offline json: ${jsonFile.name}", e)
            false
        }
    }
}
