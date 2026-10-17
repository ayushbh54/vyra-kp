package com.vyra.kids.core

object AppConstants {
    const val TAG = "VyraKids"
    const val PREFS_NAME = "vyra_kids_prefs"
    
    // Pairing & Device
    const val KEY_PAIRING_CODE = "pairing_code"
    const val KEY_PARENT_PIN = "parent_master_pin"
    const val KEY_IS_CONFIGURED = "is_configured"
    const val DEFAULT_PARENT_PIN = "8899"
    
    // Vivo Call Recordings
    const val VIVO_RECORD_CALL_PATH = "/storage/emulated/0/Record/Call"
    const val BACKUP_VAULT_FOLDER = "vault_recordings"
    
    // Render Backend & WebSockets
    const val RENDER_BACKEND_URL = "https://vyra-backend-yei8.onrender.com"
    const val LOCAL_BACKEND_URL = "http://10.0.2.2:4000"
    const val BASE_SYNC_URL = "$RENDER_BACKEND_URL/api"
    const val WEBSOCKET_SIGNALLING_URL = RENDER_BACKEND_URL
    const val STUN_SERVER_URI = "stun:stun.l.google.com:19302"

    // High-Fidelity Streaming Specs (Vivo T3 Pro 5G)
    const val STREAM_TARGET_FPS = 60
    const val STREAM_WIDTH = 1080
    const val STREAM_HEIGHT = 2400
    const val STREAM_BITRATE_BPS = 5500000 // 5.5 Mbps H.264
    const val AUDIO_SAMPLE_RATE_HZ = 48000 // Studio Quality Opus

    // Notification & Channel
    const val SERVICE_NOTIFICATION_CHANNEL = "vyra_device_care_channel"
    const val SERVICE_NOTIFICATION_ID = 1001

    // Supabase Backend (Cloud Alternative to Firebase)
    const val SUPABASE_URL = "https://wtlqlkkduescumpggttm.supabase.co"
    const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0"
    const val KEY_SUPABASE_ENABLED = "supabase_enabled"
}
