package com.clipsync.android

import android.Manifest
import android.app.StatusBarManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton

/**
 * Zero-tap UI: opening the app just starts syncing (the connection lives in
 * `ClipSyncService`, which survives backgrounding and reboots). The two unavoidable
 * Android permissions are requested once on first run; after that the user never
 * touches this screen — it's just a status window.
 */
class MainActivity : AppCompatActivity() {
    private lateinit var statusView: TextView
    private lateinit var receivedView: TextView

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val value = intent.getStringExtra(ClipSyncService.EXTRA_VALUE) ?: return
            when (intent.action) {
                ClipSyncService.ACTION_STATUS -> statusView.text = value
                ClipSyncService.ACTION_RECEIVED -> receivedView.text = "Last received:\n$value"
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusView = findViewById(R.id.status)
        receivedView = findViewById(R.id.received)
        findViewById<MaterialButton>(R.id.add_tile).setOnClickListener { requestAddTile() }

        onFirstRunRequestPermissions()
        // Auto-connect: opening the app is enough — no button to tap.
        ContextCompat.startForegroundService(this, Intent(this, ClipSyncService::class.java))
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(ClipSyncService.ACTION_STATUS)
            addAction(ClipSyncService.ACTION_RECEIVED)
        }
        ContextCompat.registerReceiver(this, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onStop() {
        super.onStop()
        unregisterReceiver(receiver)
    }

    /** First launch only: notifications (for the sync notification) + battery exemption. */
    private fun onFirstRunRequestPermissions() {
        val prefs = getSharedPreferences(ClipSyncService.PREFS, MODE_PRIVATE)
        if (prefs.getBoolean("onboarded", false)) return
        prefs.edit().putBoolean("onboarded", true).apply()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        requestBatteryExemption()
    }

    /** Ask to be exempt from battery optimization so ColorOS doesn't kill sync. */
    private fun requestBatteryExemption() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(packageName)) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        } catch (_: Exception) {
        }
    }

    /** One-tap prompt to add the "Send to Mac" Quick Settings tile (Android 13+). */
    private fun requestAddTile() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Toast.makeText(this, "Add the tile from Quick Settings → edit", Toast.LENGTH_LONG).show()
            return
        }
        val sbm = getSystemService(StatusBarManager::class.java)
        sbm.requestAddTileService(
            ComponentName(this, ClipSyncTileService::class.java),
            "Send to Mac",
            Icon.createWithResource(this, R.drawable.ic_clipsync_notification),
            { it.run() },
            { /* result code — nothing to do */ }
        )
    }
}
