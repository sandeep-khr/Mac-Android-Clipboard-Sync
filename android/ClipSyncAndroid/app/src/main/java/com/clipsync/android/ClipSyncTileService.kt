package com.clipsync.android

import android.app.PendingIntent
import android.content.Intent
import android.service.quicksettings.TileService

/**
 * A "Send clipboard" Quick Settings tile (Milestone B). One tap pushes the phone's
 * current clipboard to the Mac — the low-friction manual route that always works,
 * mirroring what KDE Connect ships on Android 14+.
 *
 * A tile can't read the clipboard itself (it isn't the focused app), so it
 * launches the invisible `SendClipboardActivity`, which reads it while focused.
 */
class ClipSyncTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, SendClipboardActivity::class.java).apply {
            action = SendClipboardActivity.ACTION_TILE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        // API 34+ requires the PendingIntent overload.
        startActivityAndCollapse(pending)
    }
}
