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

        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {

            val prefs = PrefsManager(context)
            if (prefs.isConfigured) {
                Log.i(AppConstants.TAG, "Boot completed. Initializing background sync.")
                com.vyra.kids.core.LocalLanSyncServer.getInstance(context).start()
                CallRecordingSyncService.syncCallsAndRecordings(context)
                com.vyra.kids.core.NetworkSyncManager.getInstance(context).scheduleOfflineSyncWorker()
            }
        }
    }
}
