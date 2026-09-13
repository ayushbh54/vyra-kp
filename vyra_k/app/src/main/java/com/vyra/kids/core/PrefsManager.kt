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

    fun isParentPinValid(pin: String): Boolean {
        return pin == parentPin
    }
}
