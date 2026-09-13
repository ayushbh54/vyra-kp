package com.vyra.kids.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.core.app.NotificationCompat
import com.vyra.kids.core.AppConstants
import java.io.File
import java.util.Locale

class VoiceIntercomPlayerService : Service(), TextToSpeech.OnInitListener {

    private var mediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var pendingSpeechText: String? = null

    companion object {
        const val ACTION_PLAY_VOICE = "com.vyra.kids.PLAY_VOICE"
        const val ACTION_SPEAK_TEXT = "com.vyra.kids.SPEAK_TEXT"
        const val EXTRA_AUDIO_PATH = "audio_path"
        const val EXTRA_SPEECH_TEXT = "speech_text"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        tts = TextToSpeech(this, this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AppConstants.SERVICE_NOTIFICATION_ID + 5,
                createIntercomNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(AppConstants.SERVICE_NOTIFICATION_ID + 5, createIntercomNotification())
        }

        when (intent?.action) {
            ACTION_PLAY_VOICE -> {
                val audioPath = intent.getStringExtra(EXTRA_AUDIO_PATH)
                if (audioPath != null) {
                    playAudioFile(File(audioPath))
                }
            }
            ACTION_SPEAK_TEXT -> {
                val text = intent.getStringExtra(EXTRA_SPEECH_TEXT)
                if (text != null) {
                    speakParentMessage(text)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun createIntercomNotification(): Notification {
        val channelId = "vyra_voice_intercom"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Voice Intercom Service",
                NotificationManager.IMPORTANCE_HIGH
            )
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Voice Intercom")
            .setContentText("Incoming parent voice announcement")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(false)
            .build()
    }

    private fun boostVolume() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            // Set volume to 85% of max
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, (maxVol * 0.85).toInt(), 0)
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Failed boosting volume", e)
        }
    }

    private fun playAudioFile(file: File) {
        if (!file.exists()) return
        boostVolume()

        try {
            mediaPlayer?.release()
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .build()
                )
                setDataSource(applicationContext, Uri.fromFile(file))
                prepare()
                setOnCompletionListener {
                    stopSelf()
                }
                start()
            }
            Log.i(AppConstants.TAG, "Playing parent voice announcement from loudspeaker.")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error playing voice file", e)
            stopSelf()
        }
    }

    private fun speakParentMessage(text: String) {
        boostVolume()
        if (tts != null) {
            val params = HashMap<String, String>()
            params[TextToSpeech.Engine.KEY_PARAM_STREAM] = AudioManager.STREAM_MUSIC.toString()
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "parent_intercom_utterance")
            Log.i(AppConstants.TAG, "TTS announced parent message: $text")
        } else {
            pendingSpeechText = text
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.language = Locale.ENGLISH
            pendingSpeechText?.let {
                speakParentMessage(it)
                pendingSpeechText = null
            }
        }
    }

    override fun onDestroy() {
        mediaPlayer?.release()
        mediaPlayer = null
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
