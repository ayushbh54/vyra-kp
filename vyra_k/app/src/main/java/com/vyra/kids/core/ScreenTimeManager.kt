package com.vyra.kids.core

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.util.Log
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

data class AppUsageItem(
    val packageName: String,
    val appName: String,
    val usageTimeMinutes: Long,
    val lastTimeUsed: Long
)

object ScreenTimeManager {

    fun hasUsagePermission(context: Context): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps?.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps?.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.w(AppConstants.TAG, "Error checking usage stats permission", e)
            false
        }
    }

    fun getDailyUsageStats(context: Context): List<AppUsageItem> {
        if (!hasUsagePermission(context)) return emptyList()

        val usageManager = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()

        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startTime = cal.timeInMillis
        val endTime = System.currentTimeMillis()

        val stats: List<UsageStats> = usageManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        ) ?: return emptyList()

        val pm = context.packageManager
        val items = mutableListOf<AppUsageItem>()

        for (u in stats) {
            val totalMinutes = u.totalTimeInForeground / 60000
            if (totalMinutes > 0 && u.packageName != context.packageName) {
                val appLabel = try {
                    val info = pm.getApplicationInfo(u.packageName, 0)
                    pm.getApplicationLabel(info).toString()
                } catch (_: PackageManager.NameNotFoundException) {
                    u.packageName.substringAfterLast('.').replaceFirstChar { it.uppercase() }
                }

                items.add(
                    AppUsageItem(
                        packageName = u.packageName,
                        appName = appLabel,
                        usageTimeMinutes = totalMinutes,
                        lastTimeUsed = u.lastTimeUsed
                    )
                )
            }
        }

        return items.sortedByDescending { it.usageTimeMinutes }
    }

    fun syncScreenTimeToFirebase(context: Context) {
        try {
            val usageItems = getDailyUsageStats(context)
            val childId = PrefsManager.getInstance(context).pairingCode.ifEmpty { "child_1" }
            val totalMinutes = usageItems.sumOf { it.usageTimeMinutes }

            val appsPayload = usageItems.take(20).map {
                mapOf(
                    "packageName" to it.packageName,
                    "appName" to it.appName,
                    "minutes" to it.usageTimeMinutes,
                    "lastUsed" to it.lastTimeUsed
                )
            }

            val todayDateStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

            val payload = hashMapOf(
                "date" to todayDateStr,
                "totalScreenTimeMinutes" to totalMinutes,
                "apps" to appsPayload,
                "updatedAt" to FieldValue.serverTimestamp()
            )

            FirebaseFirestore.getInstance()
                .collection("devices")
                .document(childId)
                .collection("screen_time")
                .document(todayDateStr)
                .set(payload, SetOptions.merge())
                .addOnSuccessListener {
                    Log.i(AppConstants.TAG, "ScreenTime: Synced $totalMinutes mins across ${usageItems.size} apps to Firebase")
                }
                .addOnFailureListener { e ->
                    Log.w(AppConstants.TAG, "ScreenTime: Failed to sync to Firebase", e)
                }
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncScreenTimeToFirebase", e)
        }
    }
}
