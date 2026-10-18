package com.vyra.kids.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.AppUpdateManager

/**
 * Receives silent PackageInstaller session commit callbacks after OTA APK install.
 * Registered in AndroidManifest — no UI shown to the child, fully invisible.
 */
class OtaInstallStatusReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "unknown"
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)

        when (status) {
            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(AppConstants.TAG, "OTA install SUCCESS (session=$sessionId) — app updated silently ✅")
                AppUpdateManager.clearUpdate(context)
            }
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Device requires user confirmation (e.g., device policy or restricted profile).
                // Launch the confirmation intent silently if possible — it will briefly appear.
                val confirmIntent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(confirmIntent)
                        Log.w(AppConstants.TAG, "OTA requires user confirmation — launched confirm dialog (session=$sessionId)")
                    } catch (e: Exception) {
                        Log.e(AppConstants.TAG, "Failed to launch OTA confirmation activity", e)
                    }
                }
            }
            else -> {
                Log.e(AppConstants.TAG, "OTA install FAILED (session=$sessionId, status=$status, msg=$message)")
            }
        }
    }
}
