package com.clipsync.android

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.ContextCompat

/**
 * A no-UI trampoline that pushes text to the Mac (Android→Mac). Two entry points:
 *  - **Quick Settings tile**: reads the system clipboard. Android 10+ only allows
 *    a *focused* app to read the clipboard, which is exactly why this is a real
 *    (if invisible) activity — we read once the window gains focus, then finish.
 *  - **Share sheet** (`ACTION_SEND` text/plain): uses the shared text directly, no
 *    clipboard read needed.
 *
 * Either way the text is handed to `ClipSyncService`, which sends it encrypted.
 */
class SendClipboardActivity : Activity() {

    companion object {
        const val ACTION_TILE = "com.clipsync.android.TILE"
    }

    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Share path can be handled immediately; the text is in the intent.
        if (intent?.action == Intent.ACTION_SEND) {
            dispatch(intent.getStringExtra(Intent.EXTRA_TEXT))
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Tile path: read the clipboard only once we actually have window focus.
        if (hasFocus && !handled && intent?.action != Intent.ACTION_SEND) {
            dispatch(readClipboard())
        }
    }

    private fun dispatch(text: String?) {
        if (handled) return
        handled = true
        if (text.isNullOrEmpty()) {
            Toast.makeText(this, "Nothing to send", Toast.LENGTH_SHORT).show()
        } else {
            ContextCompat.startForegroundService(
                this,
                Intent(this, ClipSyncService::class.java).apply {
                    action = ClipSyncService.ACTION_SEND_TEXT
                    putExtra(ClipSyncService.EXTRA_VALUE, text)
                }
            )
            Toast.makeText(this, "Sent to Mac", Toast.LENGTH_SHORT).show()
        }
        finish()
    }

    private fun readClipboard(): String? {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        return clipboard.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
    }
}
