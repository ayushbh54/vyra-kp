package com.vyra.kids.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.PrefsManager
import com.vyra.kids.services.CallRecordingSyncService
import com.vyra.kids.services.SmsObserverService

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON") {

            val prefs = PrefsManager(context)
            if (prefs.isConfigured) {
                Log.i(AppConstants.TAG, "Boot completed. Restarting background security monitors.")

                val callServiceIntent = Intent(context, CallRecordingSyncService::class.java)
                val smsServiceIntent = Intent(context, SmsObserverService::class.java)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(callServiceIntent)
                    context.startForegroundService(smsServiceIntent)
                } else {
                    context.startService(callServiceIntent)
                    context.startService(smsServiceIntent)
                }
            }
        }
    }
}
