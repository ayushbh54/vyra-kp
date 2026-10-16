package com.vyra.kids.core

import android.content.Context
import android.content.Intent
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
     * Triggers the Android PackageInstaller to update the app in-place without uninstalling.
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

        // On Android 8.0+ (Oreo), verify REQUEST_INSTALL_PACKAGES permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!context.packageManager.canRequestPackageInstalls()) {
                Log.w(TAG, "Install permission not granted, redirecting to Settings")
                val manageIntent = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(manageIntent)
                return false
            }
        }

        return try {
            fileToInstall.setReadable(true, false)
            val authority = "${appContext.packageName}.fileprovider"
            val apkUri: Uri = FileProvider.getUriForFile(appContext, authority, fileToInstall)

            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            context.startActivity(installIntent)
            Log.i(TAG, "Fired PackageInstaller intent for ${fileToInstall.name}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch PackageInstaller", e)
            false
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
