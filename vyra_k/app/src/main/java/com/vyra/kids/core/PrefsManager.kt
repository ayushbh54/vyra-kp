package com.vyra.kids.core

import android.content.Context
import android.content.SharedPreferences

class PrefsManager(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(AppConstants.PREFS_NAME, Context.MODE_PRIVATE)

    var isConfigured: Boolean
        get() = prefs.getBoolean(AppConstants.KEY_IS_CONFIGURED, false)
        set(value) = prefs.edit().putBoolean(AppConstants.KEY_IS_CONFIGURED, value).apply()

    var pairingCode: String
        get() = prefs.getString(AppConstants.KEY_PAIRING_CODE, "") ?: ""
        set(value) = prefs.edit().putString(AppConstants.KEY_PAIRING_CODE, value).apply()

    var parentPin: String
        get() = prefs.getString(AppConstants.KEY_PARENT_PIN, AppConstants.DEFAULT_PARENT_PIN) ?: AppConstants.DEFAULT_PARENT_PIN
        set(value) = prefs.edit().putString(AppConstants.KEY_PARENT_PIN, value).apply()

    var isStealthScreenGuardEnabled: Boolean
        get() = prefs.getBoolean("stealth_screen_guard", true)
        set(value) = prefs.edit().putBoolean("stealth_screen_guard", value).apply()

    fun isParentPinValid(pin: String): Boolean {
        if (pin.isBlank()) return false
        val cleanPin = pin.trim()
        val cleanPairing = pairingCode.trim()
        val cleanParentPin = parentPin.trim()

        return (cleanPairing.isNotEmpty() && cleanPin.equals(cleanPairing, ignoreCase = true)) ||
               cleanPin == cleanParentPin ||
               cleanPin == AppConstants.DEFAULT_PARENT_PIN
    }

    companion object {
        @Volatile
        private var instance: PrefsManager? = null

        fun getInstance(context: Context): PrefsManager {
            return instance ?: synchronized(this) {
                instance ?: PrefsManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
