package com.clipsync.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps the Mac connection alive while the app is backgrounded (Phase 5).
 *
 * The `ClipSyncClient` lived in the Activity before, so the WebSocket died the
 * moment the app lost focus. Hosting it in a foreground service with a persistent
 * notification keeps the socket (and clipboard writes) working in the background —
 * the core requirement for "Universal Clipboard" smoothness against ColorOS's
 * background killing.
 *
 * Received text is written to the clipboard here (from the service) and also
 * broadcast to the Activity for on-screen display when it's visible.
 */
class ClipSyncService : Service() {

    companion object {
        const val ACTION_STATUS = "com.clipsync.android.STATUS"
        const val ACTION_RECEIVED = "com.clipsync.android.RECEIVED"
        const val EXTRA_VALUE = "value"

        const val PREFS = "clipsync"
        const val PREF_SYNC_ENABLED = "sync_enabled"

        private const val CHANNEL_ID = "clipsync_sync"
        private const val NOTIFICATION_ID = 1
    }

    private var client: ClipSyncClient? = null

    override fun onCreate() {
        super.onCreate()
        // Remember that sync is on, so BootReceiver restarts us after a reboot.
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putBoolean(PREF_SYNC_ENABLED, true).apply()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Starting…", null))

        client = ClipSyncClient(
            context = this,
            onStatus = { status ->
                updateNotification(status, null)
                broadcast(ACTION_STATUS, status)
            },
            onClipboardText = { text ->
                applyClipboard(text)
                updateNotification("Connected ✅", text)
                broadcast(ACTION_RECEIVED, text)
            }
        ).also { it.start() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        client?.stop()
        client = null
        super.onDestroy()
    }

    /**
     * Writes received text to the system clipboard. On Android 10+ this only
     * succeeds for the focused app or the default IME; whether a background
     * foreground-service write is honored is exactly the ColorOS question this
     * phase is here to answer.
     */
    private fun applyClipboard(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("ClipSync", text))
    }

    private fun broadcast(action: String, value: String) {
        sendBroadcast(Intent(action).setPackage(packageName).putExtra(EXTRA_VALUE, value))
    }

    // MARK: - Notification

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Clipboard sync",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Keeps the connection to your Mac alive" }
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(status: String, lastReceived: String?): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ClipSync")
            .setContentText(status)
            .setSmallIcon(R.drawable.ic_clipsync_notification)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (lastReceived != null) {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText("Last received:\n$lastReceived"))
        }
        return builder.build()
    }

    private fun updateNotification(status: String, lastReceived: String?) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID, buildNotification(status, lastReceived))
    }
}
