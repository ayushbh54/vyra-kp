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

        NetworkSyncManager.getInstance(this).syncData("notifications", payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Can be used to track deleted notifications if needed
    }
}
