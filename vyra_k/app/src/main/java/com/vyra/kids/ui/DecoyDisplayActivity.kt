package com.vyra.kids.ui

import android.content.Intent
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
        disguiseManager = DisguiseManager(this)
        prefs = PrefsManager(this)

        // First run redirect: If device is not configured yet, launch Setup Wizard immediately
        if (!prefs.isConfigured) {
            startActivity(Intent(this, SetupWizardActivity::class.java))
            finish()
            return
        }

        setContentView(R.layout.activity_decoy_display)

        val tvDecoyTitle = findViewById<TextView>(R.id.tvDecoyTitle)
        val ivDecoyIcon = findViewById<ImageView>(R.id.ivDecoyIcon)
        val tvDecoyHeader = findViewById<TextView>(R.id.tvDecoyHeader)
        val tvDecoyDescription = findViewById<TextView>(R.id.tvDecoyDescription)
        val tvDecoyStatusBadge = findViewById<TextView>(R.id.tvDecoyStatusBadge)
        val ivParentUnlock = findViewById<ImageView>(R.id.ivParentUnlock)

        // Configure UI according to active disguise profile
        when (disguiseManager.getCurrentDisguise()) {
            DisguiseProfile.SIM_TOOLKIT -> {
                tvDecoyTitle.text = "System Toolkit"
                ivDecoyIcon.setImageResource(R.drawable.ic_sim_card)
                tvDecoyHeader.text = "System Services Active"
                tvDecoyDescription.text = "System diagnostic services are active and up to date.\nAll background components verified."
                tvDecoyStatusBadge.text = "System Status: Normal"
            }
            DisguiseProfile.DEVICE_SUPPORT -> {
                tvDecoyTitle.text = "Device Support"
                ivDecoyIcon.setImageResource(R.drawable.ic_device_support)
                tvDecoyHeader.text = "Diagnostics Clean"
                tvDecoyDescription.text = "No diagnostic issues found.\nAll hardware modules operating normally."
                tvDecoyStatusBadge.text = "Hardware Health: 100%"
            }
            DisguiseProfile.COMPASS -> {
                tvDecoyTitle.text = "Digital Compass"
                ivDecoyIcon.setImageResource(R.drawable.ic_compass)
                tvDecoyHeader.text = "042° NNE"
                tvDecoyDescription.text = "Magnetic sensor calibrated.\nAltitude: 214m • Accuracy: High"
                tvDecoyStatusBadge.text = "Sensor: Active"
            }
            DisguiseProfile.SYSTEM_SYNC -> {
                tvDecoyTitle.text = "System Sync"
                ivDecoyIcon.setImageResource(R.drawable.ic_sync)
                tvDecoyHeader.text = "Sync Idle"
                tvDecoyDescription.text = "Background sync status is idle.\nAll accounts up to date."
                tvDecoyStatusBadge.text = "Last Synced: 2 mins ago"
            }
            DisguiseProfile.CALCULATOR -> {
                tvDecoyTitle.text = "Calculator"
                ivDecoyIcon.setImageResource(R.drawable.ic_calculator)
                tvDecoyHeader.text = "0"
                tvDecoyDescription.text = "Standard mathematical engine ready."
                tvDecoyStatusBadge.text = "DEG • RAD"
            }
            DisguiseProfile.NOTES -> {
                tvDecoyTitle.text = "Notes"
                ivDecoyIcon.setImageResource(R.drawable.ic_notes)
                tvDecoyHeader.text = "Quick Notes"
                tvDecoyDescription.text = "No saved notes.\nAll local drafts synchronized."
                tvDecoyStatusBadge.text = "Sync: Local Storage"
            }
            DisguiseProfile.GHOST_HIDDEN -> {
                tvDecoyTitle.text = "Carrier Services"
                ivDecoyIcon.setImageResource(R.drawable.ic_sim_card)
                tvDecoyHeader.text = "SIM 1 Active (5G)"
                tvDecoyDescription.text = "Carrier network profiles verified."
                tvDecoyStatusBadge.text = "Carrier: VoLTE 5G"
            }
        }

        // 1. Discreet corner tap
        ivParentUnlock.setOnClickListener {
            showParentPinDialog()
        }

        // 2. Secret 5-Tap Gesture on center icon (Zero visible buttons needed!)
        var tapCount = 0
        var lastTapTime = 0L
        ivDecoyIcon.setOnClickListener {
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
