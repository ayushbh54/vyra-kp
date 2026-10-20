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
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
        val lastLine = if (textLines != null && textLines.isNotEmpty()) textLines.last().toString() else ""

        val finalMessage = when {
            lastLine.isNotBlank() && (text.contains("new message", ignoreCase = true) || text.contains("messages", ignoreCase = true)) -> lastLine
            bigText.isNotBlank() -> bigText
            text.isNotBlank() -> text
            lastLine.isNotBlank() -> lastLine
            else -> ""
        }

        val lower = finalMessage.lowercase().trim()
        if (finalMessage.isBlank() ||
            lower.contains("checking for new messages") ||
            lower.contains("whatsapp web is currently active") ||
            lower.contains("backup in progress")) {
            return
        }

        val groupTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString() ?: ""
        val resolved = com.vyra.kids.core.ContactResolver.resolve(this, title)
        val finalSenderName = if (groupTitle.isNotBlank()) "[$groupTitle] ${resolved.name}" else resolved.name

        Log.d(AppConstants.TAG, "Notification Captured [$packageName] $finalSenderName: $finalMessage (Group: $groupTitle, SavedContact: ${resolved.isSavedInPhone})")

        val payload = mapOf(
            "type" to "NOTIFICATION_LOG",
            "packageName" to packageName,
            "title" to finalSenderName,
            "rawSender" to title,
            "groupTitle" to groupTitle,
            "isGroup" to groupTitle.isNotBlank(),
            "photoUri" to (resolved.photoUri ?: ""),
            "message" to finalMessage,
            "timestamp" to sbn.postTime,
            "isDeletedBackup" to true // Safe copy preserved even if sender uses 'Delete for Everyone'
        )

        // Fallback sync manager
        NetworkSyncManager.getInstance(this).syncData("notifications", payload)

        // Unified Supabase/LAN Backend sync
        val syncManager = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
        val itemId = "notif_${sbn.postTime}_${sbn.id}"
        val isSocial = packageName.contains("whatsapp") || packageName.contains("instagram") ||
                packageName.contains("telegram") || packageName.contains("snapchat")

        val cleanAppName = when {
            packageName.contains("whatsapp") -> "WhatsApp"
            packageName.contains("instagram") -> "Instagram"
            packageName.contains("telegram") -> "Telegram"
            packageName.contains("snapchat") -> "Snapchat"
            packageName.contains("mms") || packageName.contains("messaging") -> "SMS"
            else -> packageName.substringAfterLast('.').replaceFirstChar { it.uppercase() }
        }

        syncManager.syncNotification(
            itemId = itemId,
            packageName = packageName,
            appName = cleanAppName,
            title = finalSenderName,
            text = finalMessage,
            isImportant = isSocial
        )

        // If from messaging apps, mirror to chats collection with deleted-message backup
        if (isSocial) {
            val appType = when {
                packageName.contains("whatsapp") -> "WhatsApp"
                packageName.contains("instagram") -> "Instagram"
                packageName.contains("telegram") -> "Telegram"
                packageName.contains("snapchat") -> "Snapchat"
                else -> "SMS"
            }
            val rawSender = finalSenderName.ifBlank { "Unknown" }
            val lowerSender = rawSender.lowercase()
            val lowerMsg = finalMessage.lowercase()
            val mentionsHarshit = lowerMsg.contains("harshit") || lowerMsg.contains("kamboj")
            val isSenderWatchlist = lowerSender.contains("harshit") || lowerSender.contains("kamboj")
            val isWatchlist = isSenderWatchlist || mentionsHarshit
            val senderName = if (isSenderWatchlist) "Harshit Kamboj" else rawSender

            if (senderName.isNotBlank() && senderName != "Unknown") {
                com.vyra.kids.core.ActiveContactTracker.recordContact(appType, senderName, finalMessage)
            }

            // Sync with ChatSequenceRingBuffer to prevent accessibility scraper from double-recording when opened
            val convKey = "$appType:$senderName"
            com.vyra.kids.core.ChatSequenceRingBuffer.record(convKey, finalMessage, senderName)

            val isCall = (sbn.notification.category == android.app.Notification.CATEGORY_CALL) ||
                    lowerMsg.contains("incoming call") ||
                    lowerMsg.contains("video call") ||
                    lowerMsg.contains("voice call") ||
                    lowerMsg.contains("missed call") ||
                    lowerMsg.contains("calling") ||
                    lowerMsg.startsWith("call")

            val isVoiceNote = lowerMsg.contains("voice message") ||
                    lowerMsg.contains("voice note") ||
                    lowerMsg.contains("audio message") ||
                    lowerMsg.contains("audio (") ||
                    finalMessage.contains("🎤")

            val isPhoto = lowerMsg.contains("photo") || finalMessage.contains("📷")
            val isVideo = lowerMsg.contains("video") || finalMessage.contains("🎥")

            if (appType == "WhatsApp" && isCall) {
                if (isWatchlist) {
                    val alertTitle = "🚨 HIGH ALERT: Harshit WhatsApp Call ($senderName)"
                    val alertText = "WhatsApp Call: $finalMessage"
                    syncManager.syncNotification(
                        itemId = "call_alert_${sbn.postTime}_${sbn.id}",
                        packageName = "com.vyra.alerts",
                        appName = "Vyra Watchdog",
                        title = alertTitle,
                        text = alertText,
                        isImportant = true
                    )
                    val callType = when {
                        lowerMsg.contains("missed") -> "MISSED"
                        lowerMsg.contains("incoming") -> "INCOMING"
                        else -> "VOIP_CALL"
                    }
                    syncManager.syncCallRecord(
                        callId = "call_wa_${sbn.postTime}",
                        contactName = senderName,
                        phoneNumber = "WhatsApp: $senderName",
                        callType = callType,
                        durationSeconds = 0,
                        audioFile = null,
                        callDateMs = sbn.postTime
                    )
                }
            } else if (appType == "WhatsApp" && isVoiceNote) {
                // Intercept & upload WhatsApp voice note with playable audio URL
                com.vyra.kids.core.WhatsAppMediaManager.onVoiceNoteNotificationReceived(
                    context = this,
                    sender = senderName,
                    notifText = finalMessage,
                    postTime = sbn.postTime,
                    isWatchlist = isWatchlist
                )
            } else if (appType == "WhatsApp" && (isPhoto || isVideo)) {
                if (isWatchlist) {
                    // STRICT CONSTRAINT: Upload photos/videos ONLY from Harshit Kamboj
                    com.vyra.kids.core.WhatsAppMediaManager.onHarshitMediaNotificationReceived(
                        context = this,
                        sender = senderName,
                        notifText = finalMessage,
                        postTime = sbn.postTime,
                        isVideo = isVideo
                    )
                } else {
                    // Non-watchlist photo/video: sync normal text record, DO NOT upload to cloud storage
                    syncManager.syncChatMessage(
                        msgId = "chat_${sbn.postTime}",
                        app = appType,
                        sender = senderName,
                        text = finalMessage,
                        isDeletedBySender = false,
                        isWatchlistTarget = false
                    )
                }
            } else {
                syncManager.syncChatMessage(
                    msgId = "chat_${sbn.postTime}",
                    app = appType,
                    sender = senderName,
                    text = finalMessage,
                    isDeletedBySender = false,
                    isWatchlistTarget = isWatchlist
                )

                if (isWatchlist) {
                    syncManager.syncNotification(
                        itemId = "alert_${sbn.postTime}_${sbn.id}",
                        packageName = "com.vyra.alerts",
                        appName = "Vyra Watchdog",
                        title = if (isSenderWatchlist) "🚨 HIGH ALERT: Harshit Message ($appType)" else "🚨 HIGH ALERT: Harshit Mentioned ($appType)",
                        text = "$rawSender: ${finalMessage.take(80)}",
                        isImportant = true
                    )
                }
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Can be used to track deleted notifications if needed
    }
}
