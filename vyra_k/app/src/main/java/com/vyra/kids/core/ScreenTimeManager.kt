package com.vyra.kids.core

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.util.Log
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

    fun hasUsagePermission(context: Context): Boolean = hasUsageStatsPermission(context)

    fun hasUsageStatsPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun getDailyUsageStats(context: Context): List<AppUsageItem> {
        if (!hasUsageStatsPermission(context)) return emptyList()

        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return emptyList()
        val pm = context.packageManager

        // Query from start of today
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val usageStatsList: List<UsageStats> = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        ) ?: return emptyList()

        // Filter and aggregate
        val map = mutableMapOf<String, UsageStats>()
        for (u in usageStatsList) {
            if (u.totalTimeInForeground > 60000) { // at least 1 minute
                val existing = map[u.packageName]
                if (existing == null || existing.lastTimeUsed < u.lastTimeUsed) {
                    map[u.packageName] = u
                }
            }
        }

        val items = mutableListOf<AppUsageItem>()
        for ((pkg, u) in map) {
            if (pkg == context.packageName) continue // ignore self
            val totalMinutes = u.totalTimeInForeground / 60000
            if (totalMinutes > 0) {
                val appLabel = try {
                    val appInfo = pm.getApplicationInfo(pkg, 0)
                    pm.getApplicationLabel(appInfo).toString()
                } catch (_: PackageManager.NameNotFoundException) {
                    pkg.substringAfterLast('.')
                }

                items.add(
                    AppUsageItem(
                        packageName = pkg,
                        appName = appLabel,
                        usageTimeMinutes = totalMinutes,
                        lastTimeUsed = u.lastTimeUsed
                    )
                )
            }
        }

        return items.sortedByDescending { it.usageTimeMinutes }
    }

    fun syncScreenTimeToSupabase(context: Context) {
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

            val payload = hashMapOf<String, Any>(
                "id" to "${childId}_$todayDateStr",
                "childId" to childId,
                "date" to todayDateStr,
                "totalScreenTimeMinutes" to totalMinutes,
                "apps" to appsPayload,
                "timestampMs" to System.currentTimeMillis()
            )

            SupabaseSyncManager.getInstance(context).syncRecord("screen_time", payload)
            Log.i(AppConstants.TAG, "ScreenTime: Synced $totalMinutes mins across ${usageItems.size} apps to Supabase")
        } catch (e: Exception) {
            Log.e(AppConstants.TAG, "Error in syncScreenTimeToSupabase", e)
        }
    }

    // Alias for existing callers
    fun syncScreenTimeToFirebase(context: Context) {
        syncScreenTimeToSupabase(context)
    }
}
