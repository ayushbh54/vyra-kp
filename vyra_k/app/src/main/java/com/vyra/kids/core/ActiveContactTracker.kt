package com.vyra.kids.core

import java.util.concurrent.ConcurrentHashMap

data class CachedChatContact(
    val contactName: String,
    val timestamp: Long,
    val lastSnippet: String = ""
)

/**
 * Shared memory tracker that bridges NotificationListener and Accessibility Scraper.
 * Allows the scraper to accurately attribute on-screen messages to the verified human contact
 * even if the app's top bar is hidden or truncated.
 */
object ActiveContactTracker {
    private val contactsMap = ConcurrentHashMap<String, CachedChatContact>()

    fun recordContact(app: String, contactName: String, snippet: String = "") {
        val cleanName = contactName.trim()
        val lower = cleanName.lowercase()
        if (cleanName.isBlank() ||
            cleanName.length < 2 ||
            lower.contains("contact") ||
            lower.contains("unknown") ||
            lower.contains("team id") ||
            lower.contains("team name") ||
            lower.contains("turn on notifications") ||
            lower.contains("never miss snaps") ||
            lower.contains("messages") ||
            lower.contains("all messages")
        ) return

        val key = normalizeApp(app)
        contactsMap[key] = CachedChatContact(
            contactName = cleanName,
            timestamp = System.currentTimeMillis(),
            lastSnippet = snippet.take(80)
        )
    }

    fun getLastContact(app: String, maxAgeMinutes: Int = 15): String? {
        val key = normalizeApp(app)
        val cached = contactsMap[key] ?: return null
        val ageMs = System.currentTimeMillis() - cached.timestamp
        if (ageMs <= maxAgeMinutes * 60 * 1000L) {
            return cached.contactName
        }
        return null
    }

    private fun normalizeApp(app: String): String {
        val lower = app.lowercase()
        return when {
            lower.contains("what") -> "WhatsApp"
            lower.contains("insta") -> "Instagram"
            lower.contains("snap") -> "Snapchat"
            lower.contains("tele") -> "Telegram"
            lower.contains("sms") || lower.contains("mms") -> "SMS"
            else -> app
        }
    }
}
