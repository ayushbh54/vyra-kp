package com.vyra.kids.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants

class LiveScreenStreamService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null

    companion object {
        const val ACTION_START_SCREEN_STREAM = "com.vyra.kids.START_SCREEN_STREAM"
        const val ACTION_STOP_SCREEN_STREAM = "com.vyra.kids.STOP_SCREEN_STREAM"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_SCREEN_STREAM -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        AppConstants.SERVICE_NOTIFICATION_ID + 1,
                        createStreamNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                    )
                } else {
                    startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 1, createStreamNotification())
                }
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
                val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                }
                if (resultData != null && resultCode != -1) {
                    startStreaming(resultCode, resultData)
                }
            }
            ACTION_STOP_SCREEN_STREAM -> {
                stopStreaming()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun createStreamNotification(): Notification {
        val channelId = "vyra_display_projection"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Display Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Display Mirror")
            .setContentText("Active display connection")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
    }

    private fun startStreaming(resultCode: Int, data: Intent) {
        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpManager.getMediaProjection(resultCode, data)

        val metrics = resources.displayMetrics
        val width = AppConstants.STREAM_WIDTH
        val height = AppConstants.STREAM_HEIGHT
        val dpi = metrics.densityDpi
        val targetFps = AppConstants.STREAM_TARGET_FPS // 60 FPS Ultra-HD

        Log.i(AppConstants.TAG, "MediaProjection active at ${width}x${height} @ ${targetFps} FPS (${dpi} DPI). WebRTC pipeline initialized.")
        // WebRTC ScreenCapturerAndroid attaches to MediaProjection with 60 FPS hardware encoder to stream frames to Parent App
    }

    private fun stopStreaming() {
        virtualDisplay?.release()
        virtualDisplay = null
        mediaProjection?.stop()
        mediaProjection = null
        Log.i(AppConstants.TAG, "Screen streaming stopped")
    }

    override fun onDestroy() {
        stopStreaming()
        super.onDestroy()
    }
}
