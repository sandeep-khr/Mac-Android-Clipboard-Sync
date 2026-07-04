package com.clipsync.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private lateinit var client: ClipSyncClient
    private lateinit var statusView: TextView
    private lateinit var receivedView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusView = findViewById(R.id.status)
        receivedView = findViewById(R.id.received)
        val connectButton = findViewById<Button>(R.id.connect)

        client = ClipSyncClient(
            context = this,
            onStatus = { message -> runOnUiThread { statusView.text = message } },
            onClipboardText = { text -> runOnUiThread { applyClipboard(text) } }
        )

        connectButton.setOnClickListener { client.start() }
    }

    /**
     * Show the received text on screen AND try to write it to the system
     * clipboard. Showing it separately matters for the spike: if the text
     * appears here but pasting elsewhere fails, we've isolated the problem to
     * ColorOS clipboard-write restrictions rather than the network path.
     */
    private fun applyClipboard(text: String) {
        receivedView.text = "Last received:\n$text"

        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("ClipSync", text))
    }

    override fun onDestroy() {
        super.onDestroy()
        client.stop()
    }
}
