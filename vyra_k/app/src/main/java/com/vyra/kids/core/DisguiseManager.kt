package com.vyra.kids.core

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log

enum class DisguiseProfile(val title: String, val aliasClass: String) {
    SIM_TOOLKIT("System Toolkit", "com.vyra.kids.AliasSimToolkit"),
    DEVICE_SUPPORT("Device Support", "com.vyra.kids.AliasDeviceSupport"),
    COMPASS("Digital Compass", "com.vyra.kids.AliasCompass"),
    SYSTEM_SYNC("System Sync", "com.vyra.kids.AliasSystemSync"),
    CALCULATOR("Calculator", "com.vyra.kids.AliasCalculator"),
    NOTES("Notes", "com.vyra.kids.AliasNotes"),
    GHOST_HIDDEN("Invisible Ghost", "")
}

class DisguiseManager(private val context: Context) {

    private val prefs = PrefsManager(context)

    fun getCurrentDisguise(): DisguiseProfile {
        val savedName = context.getSharedPreferences(AppConstants.PREFS_NAME, Context.MODE_PRIVATE)
            .getString("active_disguise", DisguiseProfile.SIM_TOOLKIT.name)
        return try {
            DisguiseProfile.valueOf(savedName ?: DisguiseProfile.SIM_TOOLKIT.name)
        } catch (e: Exception) {
            DisguiseProfile.SIM_TOOLKIT
        }
    }

    fun applyDisguise(targetProfile: DisguiseProfile) {
        val pm = context.packageManager

        for (profile in DisguiseProfile.entries) {
            if (profile.aliasClass.isBlank()) continue
            val component = ComponentName(context, profile.aliasClass)
            val state = if (profile == targetProfile) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }

            try {
                pm.setComponentEnabledSetting(
                    component,
                    state,
                    PackageManager.DONT_KILL_APP
                )
            } catch (e: Exception) {
                Log.e(AppConstants.TAG, "Error setting disguise state for ${profile.name}", e)
            }
        }

        // Save active disguise
        context.getSharedPreferences(AppConstants.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString("active_disguise", targetProfile.name)
            .apply()

        Log.i(AppConstants.TAG, "Active disguise switched to: ${targetProfile.title}")
    }

    companion object {
        fun applyDisguise(context: Context, profile: DisguiseProfile) {
            DisguiseManager(context).applyDisguise(profile)
        }
    }
}
