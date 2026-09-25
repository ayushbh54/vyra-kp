package com.vyra.kids.ui

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.vyra.kids.R
import com.vyra.kids.core.DisguiseManager
import com.vyra.kids.core.DisguiseProfile
import com.vyra.kids.core.PrefsManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DecoyDisplayActivity : AppCompatActivity() {

    private lateinit var disguiseManager: DisguiseManager
    private lateinit var prefs: PrefsManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        val ivParentUnlock = findViewById<ImageView>(R.id.ivParentUnlock)
        val tvAndroidVersion = findViewById<TextView>(R.id.tvAndroidVersion)
        val tvLastChecked = findViewById<TextView>(R.id.tvLastChecked)
        val btnCheckUpdates = findViewById<Button>(R.id.btnCheckUpdates)
        val pbChecking = findViewById<ProgressBar>(R.id.pbChecking)
        val tvDecoyFooter = findViewById<TextView>(R.id.tvDecoyFooter)

        // Populate dynamic realistic system info
        val osVersion = "Android ${Build.VERSION.RELEASE}"
        tvAndroidVersion.text = osVersion
        val currentTimeStr = "Today, " + SimpleDateFormat("hh:mm a", Locale.getDefault()).format(Date())
        tvLastChecked.text = currentTimeStr

        tvDecoyTitle.text = "System Services"
        ivDecoyIcon.setImageResource(R.drawable.ic_system_services)
        tvDecoyHeader.text = "System services are up to date"
        tvDecoyDescription.text = "Android Core Framework & Google Play system services are operating normally. No action required."
        tvDecoyFooter.text = "Android System Core • Build ${Build.ID}"

        // "Check for updates" realistic button click
        btnCheckUpdates.setOnClickListener {
            btnCheckUpdates.visibility = View.INVISIBLE
            pbChecking.visibility = View.VISIBLE

            Handler(Looper.getMainLooper()).postDelayed({
                pbChecking.visibility = View.GONE
                btnCheckUpdates.visibility = View.VISIBLE
                tvLastChecked.text = "Just now (${SimpleDateFormat("hh:mm a", Locale.getDefault()).format(Date())})"
                Toast.makeText(this, "✓ Your system is up to date", Toast.LENGTH_SHORT).show()
            }, 1200)
        }

        // 1. Discreet corner unlock
        ivParentUnlock.setOnClickListener {
            showParentPinDialog()
        }

        // 2. Secret 5-Tap Gesture on center icon
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
