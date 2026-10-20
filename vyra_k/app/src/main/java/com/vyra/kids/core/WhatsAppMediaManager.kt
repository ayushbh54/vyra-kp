package com.vyra.kids.core

import android.content.Context
import android.database.ContentObserver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.*
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.coroutines.resume

/**
 * WhatsApp Media & Voice Note Interceptor and Watchdog.
 * 
 * Features:
 * 1. Automatically captures, uploads, and links WhatsApp Voice Notes (.opus, .m4a, .mp3)
 *    so parents can listen to full voice messages in Vyra Parent app instead of just placeholder text.
 * 2. Strict Watchlist Constraint: Photos and Videos are captured and uploaded ONLY from Harshit Kamboj's
 *    chats to strictly conserve cloud and device storage. Non-watchlist media files are skipped.
 * 3. Multi-path directory watching (scoped storage Android 11+ and legacy paths).
 * 4. Screenshot Watchdog with ML Kit OCR: Scans newly created screenshots. If related to Harshit Kamboj,
 *    uploads to cloud storage and sends an instant High Alert notification to parent app. Non-Harshit screenshots
 *    are skipped to preserve privacy and quota.
 * 5. Remote Media Fetch (PULL_MEDIA): Streams requested video/media from child phone on demand.
 */
object WhatsAppMediaManager {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeObservers = CopyOnWriteArrayList<FileObserver>()
    private val processedFiles = ConcurrentHashMap.newKeySet<String>()
    private var isWatching = false
    private var screenshotContentObserver: ContentObserver? = null

    private val latinRecognizer: TextRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    private val devanagariRecognizer: TextRecognizer by lazy {
        TextRecognition.getClient(DevanagariTextRecognizerOptions.Builder().build())
    }

    // WhatsApp Media Storage Paths (Scoped Storage Android 11+ and Legacy)
    private val candidateVoiceDirs = listOf(
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes",
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Audio",
        "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Voice Notes",
        "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Audio"
    )

    private val candidateImageDirs = listOf(
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Images",
        "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Images"
    )

    private val candidateVideoDirs = listOf(
        "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video",
        "/storage/emulated/0/WhatsApp/Media/WhatsApp Video",
        "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/WhatsApp Video"
    )

    // Screenshot paths across Vivo/OriginOS, Samsung, Xiaomi, and AOSP
    private val candidateScreenshotDirs = listOf(
        "/storage/emulated/0/DCIM/Screenshots",
        "/storage/emulated/0/Pictures/Screenshots",
        "/storage/emulated/0/Screenshots",
        "/storage/emulated/0/DCIM/Screenshot"
    )

    fun isWatchlistContact(nameOrText: String): Boolean {
        val lower = nameOrText.lowercase()
        return lower.contains("harshit") || lower.contains("kamboj")
    }

    /**
     * Starts background file observation across all WhatsApp media and screenshot directories.
     */
    @Synchronized
    fun startWatching(context: Context) {
        if (isWatching) return
        isWatching = true

        val appContext = context.applicationContext

        // Observe Voice Notes directories and their date subfolders
        for (path in candidateVoiceDirs) {
            setupDirectoryObserver(appContext, File(path), "audio")
        }

        // Observe Image directories
        for (path in candidateImageDirs) {
            setupDirectoryObserver(appContext, File(path), "image")
        }

        // Observe Video directories
        for (path in candidateVideoDirs) {
            setupDirectoryObserver(appContext, File(path), "video")
        }

        // Observe Screenshot directories
        for (path in candidateScreenshotDirs) {
            setupDirectoryObserver(appContext, File(path), "screenshot")
        }

        // Fail-safe MediaStore ContentObserver for Screenshots across custom OEM paths
        setupScreenshotContentObserver(appContext)

        Log.i(AppConstants.TAG, "WhatsAppMediaManager: Active file observers initialized (${activeObservers.size} paths)")
    }

    private fun setupScreenshotContentObserver(context: Context) {
        if (screenshotContentObserver != null) return
        try {
            val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean, uri: Uri?) {
                    super.onChange(selfChange, uri)
                    checkLatestScreenshotMediaStore(context)
                }
            }
            context.contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                observer
            )
            screenshotContentObserver = observer
            Log.i(AppConstants.TAG, "WhatsAppMediaManager: MediaStore Screenshot observer registered")
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "Could not register MediaStore screenshot observer: ${e.message}")
        }
    }

    private fun checkLatestScreenshotMediaStore(context: Context) {
        scope.launch {
            try {
                val projection = arrayOf(
                    MediaStore.Images.Media._ID,
                    MediaStore.Images.Media.DATA,
                    MediaStore.Images.Media.DATE_ADDED,
                    MediaStore.Images.Media.DISPLAY_NAME
                )
                val selection = "${MediaStore.Images.Media.DATE_ADDED} >= ?"
                val selectionArgs = arrayOf(((System.currentTimeMillis() - 60_000) / 1000).toString())
                val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"

                context.contentResolver.query(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    selection,
                    selectionArgs,
                    sortOrder
                )?.use { cursor ->
                    val dataIndex = cursor.getColumnIndex(MediaStore.Images.Media.DATA)
                    val nameIndex = cursor.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    if (cursor.moveToFirst() && dataIndex != -1) {
                        val filePath = cursor.getString(dataIndex)
                        val fileName = if (nameIndex != -1) cursor.getString(nameIndex) else ""
                        if (!filePath.isNullOrBlank()) {
                            val lower = filePath.lowercase()
                            val lowerName = fileName.lowercase()
                            if (lower.contains("screenshot") || lowerName.contains("screenshot")) {
                                val file = File(filePath)
                                if (file.exists() && file.length() > 0) {
                                    handleScreenshotObserved(context, file)
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error querying MediaStore for screenshot", e)
            }
        }
    }

    private fun setupDirectoryObserver(context: Context, dir: File, mediaType: String) {
        try {
            if (!dir.exists()) {
                dir.mkdirs()
            }
            if (!dir.exists() || !dir.isDirectory) return

            val observer = createObserver(context, dir, mediaType)
            observer.startWatching()
            activeObservers.add(observer)

            // If voice directory has week subdirectories (e.g. 202642), observe them too
            if (mediaType == "audio") {
                val subdirs = dir.listFiles { f -> f.isDirectory } ?: emptyArray()
                for (sub in subdirs) {
                    val subObs = createObserver(context, sub, mediaType)
                    subObs.startWatching()
                    activeObservers.add(subObs)
                }
            }
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "Error setting up observer for ${dir.path}: ${e.message}")
        }
    }

    private fun createObserver(context: Context, targetDir: File, mediaType: String): FileObserver {
        val mask = FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO or FileObserver.CREATE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            object : FileObserver(targetDir, mask) {
                override fun onEvent(event: Int, path: String?) {
                    handleObserverEvent(context, targetDir, event, path, mediaType)
                }
            }
        } else {
            @Suppress("DEPRECATION")
            object : FileObserver(targetDir.absolutePath, mask) {
                override fun onEvent(event: Int, path: String?) {
                    handleObserverEvent(context, targetDir, event, path, mediaType)
                }
            }
        }
    }

    private fun handleObserverEvent(
        context: Context,
        parentDir: File,
        event: Int,
        path: String?,
        mediaType: String
    ) {
        if (path == null) return
        val targetFile = File(parentDir, path)

        // If a new week subdirectory is created inside Voice Notes, attach an observer to it
        if ((event and FileObserver.CREATE != 0) && targetFile.isDirectory && mediaType == "audio") {
            try {
                val newSubObs = createObserver(context, targetFile, mediaType)
                newSubObs.startWatching()
                activeObservers.add(newSubObs)
            } catch (_: Exception) {}
            return
        }

        if ((event and FileObserver.CLOSE_WRITE != 0) || (event and FileObserver.MOVED_TO != 0)) {
            if (targetFile.isFile && targetFile.length() > 0) {
                onFileObserved(context, targetFile, mediaType)
            }
        }
    }

    private fun onFileObserved(context: Context, file: File, mediaType: String) {
        val signature = "${file.name}_${file.length()}"
        if (!processedFiles.add(signature)) return

        scope.launch {
            try {
                when (mediaType) {
                    "audio" -> {
                        // Capture and sync voice notes
                        val contact = ActiveContactTracker.getLastContact("WhatsApp", 5) ?: "WhatsApp Contact"
                        val isTarget = isWatchlistContact(contact)
                        uploadAndSyncVoiceNote(context, file, contact, "🎤 Voice message", isTarget)
                    }
                    "image", "video" -> {
                        // STRICT HARSHIT FILTER: Only upload if contact is Harshit Kamboj
                        val contact = ActiveContactTracker.getLastContact("WhatsApp", 5) ?: ""
                        if (isWatchlistContact(contact)) {
                            uploadAndSyncHarshitMedia(
                                context = context,
                                file = file,
                                sender = "Harshit Kamboj",
                                notifText = if (mediaType == "video") "🎥 Video from Harshit" else "📷 Photo from Harshit",
                                isVideo = (mediaType == "video")
                            )
                        } else {
                            Log.d(AppConstants.TAG, "Skipping non-watchlist photo/video (${file.name}) to preserve storage.")
                        }
                    }
                    "screenshot" -> {
                        handleScreenshotObserved(context, file)
                    }
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error handling observed media file ${file.name}", e)
            }
        }
    }

    /**
     * Called when a WhatsApp voice note notification is received.
     * Retries scanning for the downloaded audio file and uploads it with playable audio URL.
     */
    fun onVoiceNoteNotificationReceived(
        context: Context,
        sender: String,
        notifText: String,
        postTime: Long,
        isWatchlist: Boolean
    ) {
        scope.launch {
            try {
                // Attempt 1: check immediately
                var file = findLatestVoiceNote(maxAgeMs = 120_000)
                if (file == null) {
                    delay(1200) // Allow WhatsApp to finish writing downloaded voice note to disk
                    file = findLatestVoiceNote(maxAgeMs = 120_000)
                }
                if (file == null) {
                    delay(2500) // Second retry
                    file = findLatestVoiceNote(maxAgeMs = 120_000)
                }

                if (file != null && file.exists() && file.length() > 0) {
                    uploadAndSyncVoiceNote(context, file, sender, notifText, isWatchlist)
                } else {
                    // Fallback to text record if file download wasn't accessible
                    val syncManager = FirebaseSyncManager.getInstance(context)
                    syncManager.syncChatMessage(
                        msgId = "chat_$postTime",
                        app = "WhatsApp",
                        sender = sender,
                        text = notifText,
                        isDeletedBySender = false,
                        isWatchlistTarget = isWatchlist
                    )
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in onVoiceNoteNotificationReceived", e)
            }
        }
    }

    /**
     * Called when a WhatsApp photo or video notification is received.
     * STRICT FILTER: Only executes media upload if contact is Harshit Kamboj.
     */
    fun onHarshitMediaNotificationReceived(
        context: Context,
        sender: String,
        notifText: String,
        postTime: Long,
        isVideo: Boolean
    ) {
        val isHarshit = isWatchlistContact(sender) || isWatchlistContact(notifText)
        if (!isHarshit) {
            // STRICT STORAGE SAFETY: Do not upload non-Harshit media
            val syncManager = FirebaseSyncManager.getInstance(context)
            syncManager.syncChatMessage(
                msgId = "chat_$postTime",
                app = "WhatsApp",
                sender = sender,
                text = notifText,
                isDeletedBySender = false,
                isWatchlistTarget = false
            )
            return
        }

        scope.launch {
            try {
                var file = if (isVideo) findLatestVideo(maxAgeMs = 120_000) else findLatestPhoto(maxAgeMs = 120_000)
                if (file == null) {
                    delay(1200)
                    file = if (isVideo) findLatestVideo(maxAgeMs = 120_000) else findLatestPhoto(maxAgeMs = 120_000)
                }
                if (file == null) {
                    delay(2500)
                    file = if (isVideo) findLatestVideo(maxAgeMs = 120_000) else findLatestPhoto(maxAgeMs = 120_000)
                }

                if (file != null && file.exists() && file.length() > 0) {
                    uploadAndSyncHarshitMedia(context, file, sender, notifText, isVideo = isVideo)
                } else {
                    val syncManager = FirebaseSyncManager.getInstance(context)
                    syncManager.syncChatMessage(
                        msgId = "chat_$postTime",
                        app = "WhatsApp",
                        sender = sender,
                        text = notifText,
                        isDeletedBySender = false,
                        isWatchlistTarget = true
                    )
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in onHarshitMediaNotificationReceived", e)
            }
        }
    }

    /**
     * Called when accessibility scraper detects a voice note node inside an active WhatsApp conversation.
     */
    fun onVoiceNoteDetectedInActiveChat(
        context: Context,
        contactName: String,
        text: String,
        isWatchlist: Boolean
    ) {
        scope.launch {
            try {
                val file = findLatestVoiceNote(maxAgeMs = 60_000)
                if (file != null && file.exists() && file.length() > 0) {
                    uploadAndSyncVoiceNote(context, file, contactName, text, isWatchlist)
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in onVoiceNoteDetectedInActiveChat", e)
            }
        }
    }

    /**
     * Called when accessibility scraper detects photo/video inside Harshit Kamboj's conversation.
     */
    fun onHarshitMediaDetectedInActiveChat(
        context: Context,
        contactName: String,
        text: String,
        isVideo: Boolean
    ) {
        if (!isWatchlistContact(contactName)) return

        scope.launch {
            try {
                val file = if (isVideo) findLatestVideo(maxAgeMs = 60_000) else findLatestPhoto(maxAgeMs = 60_000)
                if (file != null && file.exists() && file.length() > 0) {
                    uploadAndSyncHarshitMedia(context, file, contactName, text, isVideo = isVideo)
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in onHarshitMediaDetectedInActiveChat", e)
            }
        }
    }

    /**
     * Periodically scans for recent voice notes that may have been received during sleep or boot.
     */
    fun scanRecentVoiceNotes(context: Context) {
        scope.launch {
            try {
                val file = findLatestVoiceNote(maxAgeMs = 300_000)
                if (file != null) {
                    val signature = "${file.name}_${file.length()}"
                    if (processedFiles.add(signature)) {
                        val contact = ActiveContactTracker.getLastContact("WhatsApp", 10) ?: "WhatsApp Contact"
                        uploadAndSyncVoiceNote(context, file, contact, "🎤 Voice message", isWatchlistContact(contact))
                    }
                }
            } catch (_: Exception) {}
        }
    }

    private fun uploadAndSyncVoiceNote(
        context: Context,
        file: File,
        sender: String,
        notifText: String,
        isWatchlist: Boolean
    ) {
        val signature = "${file.name}_${file.length()}"
        processedFiles.add(signature)

        val cleanSender = if (isWatchlist) "Harshit Kamboj" else sender.ifBlank { "WhatsApp Contact" }
        var duration = parseDurationFromText(notifText)
        if (duration <= 0) {
            duration = getAudioDuration(file)
        }

        val displaySnippet = if (duration > 0) "🎤 Voice message (${duration}s)" else "🎤 Voice message"
        val syncManager = FirebaseSyncManager.getInstance(context)
        val msgId = "voice_${System.currentTimeMillis()}_${file.nameWithoutExtension.takeLast(6)}"

        syncManager.uploadMediaAndSyncChatMessage(
            msgId = msgId,
            app = "WhatsApp",
            sender = cleanSender,
            text = displaySnippet,
            mediaFile = file,
            mediaType = "audio",
            isViewOnce = false,
            isIncoming = !file.absolutePath.contains("/Sent/"),
            isDeletedBySender = false,
            isWatchlistTarget = isWatchlist,
            voiceNoteDurationSeconds = duration
        )

        if (isWatchlist) {
            syncManager.syncNotification(
                itemId = "alert_${System.currentTimeMillis()}",
                packageName = "com.vyra.alerts",
                appName = "Vyra Watchdog",
                title = "🚨 HIGH ALERT: Harshit Voice Message (WhatsApp)",
                text = "$cleanSender: $displaySnippet",
                isImportant = true
            )
        }

        Log.i(AppConstants.TAG, "Uploaded and synced WhatsApp voice note: ${file.name} ($duration s) for $cleanSender")
    }

    private fun uploadAndSyncHarshitMedia(
        context: Context,
        file: File,
        sender: String,
        notifText: String,
        isVideo: Boolean
    ) {
        val signature = "${file.name}_${file.length()}"
        processedFiles.add(signature)

        val cleanSender = "Harshit Kamboj"
        val mediaType = if (isVideo) "video" else "image"
        val displaySnippet = if (isVideo) "🎥 [Video from Harshit Kamboj]" else "📷 [Photo from Harshit Kamboj]"
        val syncManager = FirebaseSyncManager.getInstance(context)
        val msgId = "media_${System.currentTimeMillis()}_${file.nameWithoutExtension.takeLast(6)}"

        syncManager.uploadMediaAndSyncChatMessage(
            msgId = msgId,
            app = "WhatsApp",
            sender = cleanSender,
            text = displaySnippet,
            mediaFile = file,
            mediaType = mediaType,
            isViewOnce = false,
            isIncoming = !file.absolutePath.contains("/Sent/"),
            isDeletedBySender = false,
            isWatchlistTarget = true
        )

        syncManager.syncNotification(
            itemId = "alert_${System.currentTimeMillis()}",
            packageName = "com.vyra.alerts",
            appName = "Vyra Watchdog",
            title = "🚨 HIGH ALERT: Harshit Shared Media (WhatsApp)",
            text = "$cleanSender: $displaySnippet",
            isImportant = true
        )

        Log.i(AppConstants.TAG, "Uploaded and synced Harshit media ($mediaType): ${file.name}")
    }

    private fun findLatestVoiceNote(maxAgeMs: Long): File? {
        val audioExts = setOf("opus", "m4a", "mp3", "aac", "ogg")
        return findLatestFile(candidateVoiceDirs, audioExts, maxAgeMs)
    }

    private fun findLatestPhoto(maxAgeMs: Long): File? {
        val imgExts = setOf("jpg", "jpeg", "png", "webp")
        return findLatestFile(candidateImageDirs, imgExts, maxAgeMs)
    }

    private fun findLatestVideo(maxAgeMs: Long): File? {
        val vidExts = setOf("mp4", "3gp", "mkv")
        return findLatestFile(candidateVideoDirs, vidExts, maxAgeMs)
    }

    private fun findLatestFile(dirs: List<String>, extensions: Set<String>, maxAgeMs: Long): File? {
        val now = System.currentTimeMillis()
        var latestFile: File? = null
        var latestModified = 0L

        for (dirPath in dirs) {
            val root = File(dirPath)
            if (!root.exists() || !root.isDirectory) continue

            // Check immediate files and 1 level of subdirectories
            val filesToScan = mutableListOf<File>()
            val items = root.listFiles() ?: continue
            for (item in items) {
                if (item.isFile) {
                    filesToScan.add(item)
                } else if (item.isDirectory) {
                    val subItems = item.listFiles() ?: continue
                    for (sub in subItems) {
                        if (sub.isFile) filesToScan.add(sub)
                    }
                }
            }

            for (f in filesToScan) {
                val ext = f.extension.lowercase()
                if (ext in extensions && f.length() > 0) {
                    val modified = f.lastModified()
                    if (now - modified <= maxAgeMs && modified > latestModified) {
                        latestModified = modified
                        latestFile = f
                    }
                }
            }
        }
        return latestFile
    }

    private fun parseDurationFromText(text: String): Int {
        return try {
            val match = Regex("""(?:\(|\s)(\d{1,2}):(\d{2})(?:\)|\s|$)""").find(text)
            if (match != null) {
                val min = match.groupValues[1].toInt()
                val sec = match.groupValues[2].toInt()
                min * 60 + sec
            } else {
                0
            }
        } catch (_: Exception) {
            0
        }
    }

    private fun getAudioDuration(file: File): Int {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(file.absolutePath)
            val durStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val ms = durStr?.toLongOrNull() ?: 0L
            (ms / 1000).toInt()
        } catch (_: Exception) {
            0
        } finally {
            try { retriever.release() } catch (_: Exception) {}
        }
    }

    /**
     * Processes an observed screenshot file.
     * Uses ML Kit OCR (Latin + Devanagari) to extract on-screen text.
     * If the screenshot mentions Harshit Kamboj or recent contact was Harshit, uploads to cloud and triggers
     * an instant High Alert Watchdog notification.
     * Non-Harshit screenshots are ignored to strictly conserve cloud storage and protect privacy.
     */
    private fun handleScreenshotObserved(context: Context, file: File) {
        val signature = "screenshot_${file.name}_${file.length()}"
        if (!processedFiles.add(signature)) return

        scope.launch {
            try {
                // Short debounce to ensure file write completion
                delay(800)
                if (!file.exists() || file.length() == 0L) return@launch

                val ext = file.extension.lowercase()
                if (ext !in setOf("jpg", "jpeg", "png", "webp")) return@launch

                // Downsample decode to preserve RAM
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, options)
                val maxDim = maxOf(options.outWidth, options.outHeight)
                var sampleSize = 1
                while (maxDim / sampleSize > 1600) {
                    sampleSize *= 2
                }
                val decodeOptions = BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                }
                val bitmap = BitmapFactory.decodeFile(file.absolutePath, decodeOptions) ?: return@launch

                val inputImage = InputImage.fromBitmap(bitmap, 0)
                val latinVisionText = recognizeVisionText(latinRecognizer, inputImage)
                val latinText = latinVisionText?.text ?: ""

                // If Latin didn't detect Harshit, run Devanagari pass as well
                val devanagariText = if (!isWatchlistContact(latinText)) {
                    recognizeVisionText(devanagariRecognizer, inputImage)?.text ?: ""
                } else ""

                val fullOcrText = "$latinText\n$devanagariText".trim()

                val activeContact = ActiveContactTracker.getLastContact("WhatsApp", 5)
                    ?: ActiveContactTracker.getLastContact("Snapchat", 5)
                    ?: ActiveContactTracker.getLastContact("Instagram", 5)
                    ?: ""

                val isHarshitRelated = isWatchlistContact(fullOcrText) || isWatchlistContact(activeContact)

                if (isHarshitRelated) {
                    Log.i(AppConstants.TAG, "Harshit-related screenshot identified! OCR length=${fullOcrText.length}")

                    val relevantSnippet = fullOcrText.lines()
                        .map { it.trim() }
                        .filter { it.isNotBlank() && isWatchlistContact(it) }
                        .take(2)
                        .joinToString(" | ")
                        .ifBlank { "Screenshot captured involving Harshit Kamboj" }

                    val syncManager = FirebaseSyncManager.getInstance(context)
                    val msgId = "screenshot_${System.currentTimeMillis()}_${file.nameWithoutExtension.takeLast(6)}"

                    syncManager.uploadMediaAndSyncChatMessage(
                        msgId = msgId,
                        app = "Screenshot",
                        sender = "Harshit Kamboj",
                        text = "📸 [Harshit Screenshot]: $relevantSnippet",
                        mediaFile = file,
                        mediaType = "image",
                        isViewOnce = false,
                        isIncoming = false,
                        isDeletedBySender = false,
                        isWatchlistTarget = true
                    )

                    syncManager.syncNotification(
                        itemId = "alert_${System.currentTimeMillis()}",
                        packageName = "com.vyra.alerts",
                        appName = "Vyra Watchdog",
                        title = "🚨 HIGH ALERT: Harshit Screenshot Detected",
                        text = "Screenshot taken on child's phone involving Harshit: $relevantSnippet",
                        isImportant = true
                    )
                    Log.i(AppConstants.TAG, "Uploaded & notified Harshit screenshot: ${file.name}")
                } else {
                    Log.d(AppConstants.TAG, "Non-Harshit screenshot (${file.name}) skipped to strictly preserve storage and privacy.")
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error processing screenshot ${file.name}", e)
            }
        }
    }

    private suspend fun recognizeVisionText(recognizer: TextRecognizer, image: InputImage): com.google.mlkit.vision.text.Text? =
        suspendCancellableCoroutine { cont ->
            recognizer.process(image)
                .addOnSuccessListener { text ->
                    if (cont.isActive) cont.resume(text)
                }
                .addOnFailureListener {
                    if (cont.isActive) cont.resume(null)
                }
        }

    /**
     * Triggered by parent app's "⚡ Fetch & Play Video Now" (PULL_MEDIA command).
     * Uploads the latest video/media file and updates the message record so parent can stream it.
     */
    fun fetchAndUploadRecentMedia(
        context: Context,
        contactName: String,
        isVideo: Boolean,
        requestedMsgId: String = ""
    ) {
        scope.launch {
            try {
                Log.i(AppConstants.TAG, "Processing PULL_MEDIA for contact '$contactName' (isVideo: $isVideo, msgId: '$requestedMsgId')")
                val file = if (isVideo) findLatestVideo(maxAgeMs = 3600_000 * 48) else findLatestPhoto(maxAgeMs = 3600_000 * 48)
                if (file != null && file.exists() && file.length() > 0) {
                    val cleanSender = if (isWatchlistContact(contactName)) "Harshit Kamboj" else contactName.ifBlank { "WhatsApp Contact" }
                    val mediaType = if (isVideo) "video" else "image"
                    val displaySnippet = if (isVideo) "🎥 [Video from $cleanSender]" else "📷 [Photo from $cleanSender]"
                    val syncManager = FirebaseSyncManager.getInstance(context)
                    val targetMsgId = requestedMsgId.ifBlank {
                        "media_pull_${System.currentTimeMillis()}_${file.nameWithoutExtension.takeLast(6)}"
                    }

                    syncManager.uploadMediaAndSyncChatMessage(
                        msgId = targetMsgId,
                        app = "WhatsApp",
                        sender = cleanSender,
                        text = displaySnippet,
                        mediaFile = file,
                        mediaType = mediaType,
                        isViewOnce = false,
                        isIncoming = !file.absolutePath.contains("/Sent/"),
                        isDeletedBySender = false,
                        isWatchlistTarget = isWatchlistContact(cleanSender)
                    )
                    Log.i(AppConstants.TAG, "PULL_MEDIA success: Uploaded ${file.name} for msgId: $targetMsgId")
                } else {
                    Log.w(AppConstants.TAG, "PULL_MEDIA: No matching video/photo found on device within past 48h")
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error in fetchAndUploadRecentMedia", e)
            }
        }
    }
}
