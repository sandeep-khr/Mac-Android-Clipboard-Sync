package com.clipsync.android

import android.Manifest
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper

/**
 * Automatic Android→Mac capture (Milestone B3) — the KDE-Connect-proven trick for
 * reading the clipboard in the background without root.
 *
 * Android 10+ won't let a background app read the clipboard, and won't even
 * deliver the clip-changed callback. But if the app *declares interest*
 * (registers a listener), the system logs a "denying clipboard access" line each
 * time the clipboard changes while we're not focused. With a one-time
 * `READ_LOGS` grant (see mac/setup-android-auto.sh) we watch our own logcat for
 * that line and briefly raise an invisible focused window
 * (`SendClipboardActivity`) — which *is* allowed to read the clipboard — then
 * push it. Raising the window from the background needs `SYSTEM_ALERT_WINDOW`,
 * also granted once via adb.
 *
 * If the grants aren't present, `start()` returns false and we simply fall back
 * to the manual tile / share routes.
 *
 * NOTE: the exact denial-line format varies by OEM/version; the matcher below is
 * broad and is tuned against the real device's logcat.
 */
class ClipboardMonitor(private val context: Context) {

    private val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val handler = Handler(Looper.getMainLooper())
    private val packageName = context.packageName

    @Volatile private var running = false
    private var watcherThread: Thread? = null
    private var lastLaunch = 0L

    // Registering this is what makes the system attempt (and log the denial of) a
    // clipboard read on every copy while we're backgrounded.
    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        // If it ever fires directly (foreground / default IME), capture right away.
        launchCapture()
    }

    /** @return true if auto-capture started; false if the READ_LOGS grant is missing. */
    fun start(): Boolean {
        if (context.checkSelfPermission(Manifest.permission.READ_LOGS) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        if (running) return true
        running = true
        try {
            clipboard.addPrimaryClipChangedListener(clipListener)
        } catch (_: Exception) {
        }
        watcherThread = Thread(::watchLogcat).apply { isDaemon = true; start() }
        return true
    }

    fun stop() {
        running = false
        try {
            clipboard.removePrimaryClipChangedListener(clipListener)
        } catch (_: Exception) {
        }
        watcherThread?.interrupt()
        watcherThread = null
    }

    private fun watchLogcat() {
        try {
            val process = Runtime.getRuntime().exec(arrayOf("logcat", "-v", "brief"))
            process.inputStream.bufferedReader().use { reader ->
                while (running) {
                    val line = reader.readLine() ?: break
                    if (isClipboardDenial(line)) launchCapture()
                }
            }
        } catch (_: Exception) {
            // logcat exec failed (no READ_LOGS after all) — manual routes still work.
        }
    }

    /** Broad matcher for the system's "denied clipboard read" line for our app. */
    private fun isClipboardDenial(line: String): Boolean {
        val l = line.lowercase()
        return l.contains("clipboard") &&
            l.contains(packageName) &&
            (l.contains("denying") || l.contains("denied") || l.contains("not in focus"))
    }

    private fun launchCapture() {
        val now = System.currentTimeMillis()
        if (now - lastLaunch < 800) return // debounce the burst of log lines per copy
        lastLaunch = now
        handler.post {
            val intent = Intent(context, SendClipboardActivity::class.java).apply {
                action = SendClipboardActivity.ACTION_TILE
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            try {
                context.startActivity(intent)
            } catch (_: Exception) {
                // Needs SYSTEM_ALERT_WINDOW to launch from background; falls back to manual.
            }
        }
    }
}
