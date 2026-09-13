package com.vyra.kids.receivers

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.NetworkSyncManager

class VyraDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(AppConstants.TAG, "Device Administrator Active. Uninstall protection enabled.")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        Log.w(AppConstants.TAG, "Device Administrator deactivation attempted!")

        // Dispatch tamper alert to parent
        val payload = mapOf(
            "type" to "TAMPER_ALERT",
            "title" to "Uninstall Protection Triggered",
            "message" to "Child requested to deactivate Device Administrator.",
            "timestamp" to System.currentTimeMillis()
        )
        NetworkSyncManager.getInstance(context).syncData("alerts", payload)

        return "Warning: Deactivating Device Administrator will disable system care security services. Parent PIN is required."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(AppConstants.TAG, "Device Administrator Disabled.")
    }
}
