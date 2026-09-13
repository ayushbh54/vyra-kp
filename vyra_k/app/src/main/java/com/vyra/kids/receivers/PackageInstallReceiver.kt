package com.vyra.kids.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.NetworkSyncManager

class PackageInstallReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (intent.action == Intent.ACTION_PACKAGE_ADDED) {
            val packageName = intent.data?.schemeSpecificPart ?: return
            val pm = context.packageManager

            val appName = try {
                val appInfo = pm.getApplicationInfo(packageName, 0)
                pm.getApplicationLabel(appInfo).toString()
            } catch (e: PackageManager.NameNotFoundException) {
                packageName
            }

            Log.i(AppConstants.TAG, "New App Installed Detected: $appName ($packageName)")

            val payload = mapOf(
                "type" to "NEW_APP_INSTALLED",
                "appName" to appName,
                "packageName" to packageName,
                "timestamp" to System.currentTimeMillis()
            )
            NetworkSyncManager.getInstance(context).syncData("alerts", payload)
        }
    }
}
