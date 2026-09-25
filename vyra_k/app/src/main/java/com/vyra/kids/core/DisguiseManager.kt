package com.vyra.kids.core

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log

enum class DisguiseProfile(val title: String, val aliasClass: String) {
    VIVO_SERVICES("vivo services", "com.vyra.kids.AliasVivoServices"),
    SAMSUNG_SERVICES("Samsung Services", "com.vyra.kids.AliasSamsungServices"),
    XIAOMI_SERVICES("Xiaomi Services", "com.vyra.kids.AliasXiaomiServices"),
    SIM_TOOLKIT("System Services", "com.vyra.kids.AliasSimToolkit"),
    DEVICE_SUPPORT("Device Support", "com.vyra.kids.AliasDeviceSupport"),
    COMPASS("Digital Compass", "com.vyra.kids.AliasCompass"),
    SYSTEM_SYNC("System Sync", "com.vyra.kids.AliasSystemSync"),
    CALCULATOR("Calculator", "com.vyra.kids.AliasCalculator"),
    NOTES("Notes", "com.vyra.kids.AliasNotes"),
    GHOST_HIDDEN("Invisible Ghost", "")
}

class DisguiseManager(private val context: Context) {

    private val prefs = PrefsManager(context)

    fun getHardwareBrandDisguise(): DisguiseProfile {
        val manufacturer = android.os.Build.MANUFACTURER.lowercase()
        return when {
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> DisguiseProfile.VIVO_SERVICES
            manufacturer.contains("samsung") -> DisguiseProfile.SAMSUNG_SERVICES
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> DisguiseProfile.XIAOMI_SERVICES
            else -> DisguiseProfile.SIM_TOOLKIT
        }
    }

    fun getCurrentDisguise(): DisguiseProfile {
        val defaultProfile = getHardwareBrandDisguise()
        val savedName = context.getSharedPreferences(AppConstants.PREFS_NAME, Context.MODE_PRIVATE)
            .getString("active_disguise", defaultProfile.name)
        return try {
            DisguiseProfile.valueOf(savedName ?: defaultProfile.name)
        } catch (e: Exception) {
            defaultProfile
        }
    }

    fun autoApplyBrandDisguise() {
        val target = getHardwareBrandDisguise()
        val current = getCurrentDisguise()
        val isBrandOrSystem = current == DisguiseProfile.VIVO_SERVICES ||
                current == DisguiseProfile.SAMSUNG_SERVICES ||
                current == DisguiseProfile.XIAOMI_SERVICES ||
                current == DisguiseProfile.SIM_TOOLKIT
        if (isBrandOrSystem && current != target) {
            applyDisguise(target)
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
