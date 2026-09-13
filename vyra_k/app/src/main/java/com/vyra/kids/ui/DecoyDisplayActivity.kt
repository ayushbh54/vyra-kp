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
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_decoy_display)

        disguiseManager = DisguiseManager(this)
        prefs = PrefsManager(this)

        val tvDecoyTitle = findViewById<TextView>(R.id.tvDecoyTitle)
        val ivDecoyIcon = findViewById<ImageView>(R.id.ivDecoyIcon)
        val tvDecoyHeader = findViewById<TextView>(R.id.tvDecoyHeader)
        val tvDecoyDescription = findViewById<TextView>(R.id.tvDecoyDescription)
        val tvDecoyStatusBadge = findViewById<TextView>(R.id.tvDecoyStatusBadge)
        val ivParentUnlock = findViewById<ImageView>(R.id.ivParentUnlock)

        // Configure UI according to active disguise profile
        when (disguiseManager.getCurrentDisguise()) {
            DisguiseProfile.SIM_TOOLKIT -> {
                tvDecoyTitle.text = "SIM Toolkit"
                ivDecoyIcon.setImageResource(R.drawable.ic_sim_card)
                tvDecoyHeader.text = "SIM Services Active"
                tvDecoyDescription.text = "SIM Services are active and up to date.\nNetwork carrier profiles verified."
                tvDecoyStatusBadge.text = "Carrier Status: Normal (5G)"
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
        }

        // Secret unlock button for Parent Master PIN
        ivParentUnlock.setOnClickListener {
            showParentPinDialog()
        }
    }

    private fun showParentPinDialog() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
            hint = "Enter 4-digit Master PIN"
        }

        AlertDialog.Builder(this)
            .setTitle("Parent Verification")
            .setMessage("Enter your secret parent PIN to manage disguise or settings:")
            .setView(input)
            .setPositiveButton("Verify") { dialog, _ ->
                val enteredPin = input.text.toString().trim()
                if (prefs.isParentPinValid(enteredPin)) {
                    Toast.makeText(this, "Access Granted", Toast.LENGTH_SHORT).show()
                    showDisguisePickerSheet()
                } else {
                    Toast.makeText(this, "Incorrect PIN!", Toast.LENGTH_SHORT).show()
                }
                dialog.dismiss()
            }
            .setNegativeButton("Cancel") { dialog, _ ->
                dialog.dismiss()
            }
            .show()
    }

    private fun showDisguisePickerSheet() {
        val disguises = DisguiseProfile.values()
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
