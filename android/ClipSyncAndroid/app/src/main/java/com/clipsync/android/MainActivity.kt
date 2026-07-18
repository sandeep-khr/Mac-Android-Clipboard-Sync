package com.clipsync.android

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

/**
 * Thin UI: a Connect button that starts the foreground sync service, plus two
 * text views that mirror the service's status / last-received via broadcasts.
 *
 * The connection itself lives in `ClipSyncService` (Phase 5) so it survives the
 * activity being backgrounded — the Activity is now just a window onto it.
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
        findViewById<Button>(R.id.connect).setOnClickListener { startSync() }
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

    private fun startSync() {
        // The foreground-service notification needs POST_NOTIFICATIONS on 13+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        requestBatteryExemption()
        statusView.text = "Starting sync service…"
        ContextCompat.startForegroundService(this, Intent(this, ClipSyncService::class.java))
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
            // Some OEMs don't expose this screen; the setup guidance covers it manually.
        }
    }
}
