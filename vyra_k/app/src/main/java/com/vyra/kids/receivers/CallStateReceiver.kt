package com.vyra.kids.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.telephony.TelephonyManager
import android.util.Log
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.PrefsManager
import com.vyra.kids.services.CallRecordingSyncService

/**
 * Event-Driven Call State Receiver.
 * Listens for call completion without requiring any 24/7 background service.
 * Consumes 0% idle battery.
 */
class CallStateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        val stateStr = intent.getStringExtra(TelephonyManager.EXTRA_STATE)
        Log.d(AppConstants.TAG, "CallStateReceiver event: state=$stateStr")

        if (stateStr == TelephonyManager.EXTRA_STATE_IDLE) {
            val prefs = PrefsManager(context)
            if (!prefs.isConfigured) return

            // Give the dialer & audio recorder 2.5 seconds to flush call log & save file to disk
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    Log.i(AppConstants.TAG, "Call ended. Running on-demand call log and recording sync...")
                    CallRecordingSyncService.syncCallsAndRecordings(context)
                } catch (e: Exception) {
                    Log.e(AppConstants.TAG, "Error syncing call post-completion", e)
                }
            }, 2500)
        }
    }
}
