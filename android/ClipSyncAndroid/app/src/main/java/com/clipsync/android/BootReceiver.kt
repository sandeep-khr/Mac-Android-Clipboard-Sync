package com.clipsync.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Restarts the sync service after a reboot so the connection is up without the
 * user reopening the app (Milestone A — ColorOS survival). Only fires if sync was
 * previously enabled; ColorOS also requires "Allow Auto Start-up" for this
 * broadcast to be delivered at all (surfaced in the app's setup guidance).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val enabled = context
            .getSharedPreferences(ClipSyncService.PREFS, Context.MODE_PRIVATE)
            .getBoolean(ClipSyncService.PREF_SYNC_ENABLED, false)
        if (enabled) {
            ContextCompat.startForegroundService(context, Intent(context, ClipSyncService::class.java))
        }
    }
}
