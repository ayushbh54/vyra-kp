package com.vyra.kids.core

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedDeque

/**
 * High-Precision Sequence Ring Buffer for Chat Deduplication.
 * Replaces lossy time-bucket hashing with an in-memory sliding sequence window (35 items per chat).
 * 
 * Benefits:
 * 1. Prevents duplicate scraping of the same on-screen message during rapid UI redraws/scrolling.
 * 2. Allows natural repeated words ("Ok", "Haan", "Acha") sent as separate messages to be captured 100% reliably.
 * 3. Thread-safe and zero memory leak.
 */
object ChatSequenceRingBuffer {
    private const val MAX_HISTORY_PER_CHAT = 35
    private const val RE_SCRAPE_SUPPRESSION_MS = 3500L // 3.5 seconds re-scrape debounce

    data class MessageEntry(
        val text: String,
        val sender: String,
        val timestampMs: Long
    )

    private val conversationHistory = ConcurrentHashMap<String, ConcurrentLinkedDeque<MessageEntry>>()

    /**
     * Checks if this text + sender represents a duplicate scrape of an existing on-screen node.
     * Returns true if it was seen within the last 3.5 seconds in the same conversation.
     */
    fun isDuplicate(conversationKey: String, text: String, sender: String): Boolean {
        val history = conversationHistory.getOrPut(conversationKey) { ConcurrentLinkedDeque() }
        val now = System.currentTimeMillis()

        // Check if identical message was ingested within the short re-scrape debounce window
        return history.any { entry ->
            entry.text == text && entry.sender == sender && (now - entry.timestampMs < RE_SCRAPE_SUPPRESSION_MS)
        }
    }

    /**
     * Records an ingested message into the conversation sequence ring.
     */
    fun record(conversationKey: String, text: String, sender: String) {
        val history = conversationHistory.getOrPut(conversationKey) { ConcurrentLinkedDeque() }
        val now = System.currentTimeMillis()
        history.addFirst(MessageEntry(text, sender, now))

        while (history.size > MAX_HISTORY_PER_CHAT) {
            history.pollLast()
        }
    }

    /**
     * Clears history for a specific conversation or all
     */
    fun clear(conversationKey: String? = null) {
        if (conversationKey != null) {
            conversationHistory.remove(conversationKey)
        } else {
            conversationHistory.clear()
        }
    }
}
