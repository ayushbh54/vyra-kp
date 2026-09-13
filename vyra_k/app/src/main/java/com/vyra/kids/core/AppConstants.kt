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
    
    // Server Endpoints & WebSocket / Firebase
    const val BASE_SYNC_URL = "https://vyra-parent-sync.internal/api/v1"
    const val WEBSOCKET_SIGNALLING_URL = "wss://vyra-parent-sync.internal/ws"
    
    // Notification & Channel
    const val SERVICE_NOTIFICATION_CHANNEL = "vyra_device_care_channel"
    const val SERVICE_NOTIFICATION_ID = 1001
}
