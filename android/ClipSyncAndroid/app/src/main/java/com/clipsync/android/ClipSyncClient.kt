package com.clipsync.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject

/**
 * The whole receiver in one class (spike scope):
 *  1. discover the Mac via NSD (`_clipsync._tcp`)
 *  2. connect to it over WebSocket
 *  3. parse `clipboard_update` and hand the text back to the UI
 *
 * No pairing, no crypto, no reconnect yet — that's Phase 4+. This exists only to
 * answer "copy on Mac -> does it reach the Oppo?".
 *
 * Callbacks fire on background threads; the UI layer is responsible for hopping
 * to the main thread.
 */
class ClipSyncClient(
    context: Context,
    private val onStatus: (String) -> Unit,
    private val onClipboardText: (String) -> Unit
) {
    private val serviceType = "_clipsync._tcp."
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val httpClient = OkHttpClient()

    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var webSocket: WebSocket? = null
    private var resolving = false
    private var connected = false

    fun start() {
        onStatus("Searching for your Mac…")
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}

            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("_clipsync") && !connected) {
                    resolve(service)
                }
            }

            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                onStatus("Discovery failed (code $errorCode)")
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        discoveryListener = listener
        nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun resolve(service: NsdServiceInfo) {
        if (resolving) return
        resolving = true
        nsdManager.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                resolving = false
                onStatus("Resolve failed (code $errorCode)")
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                resolving = false
                val host = serviceInfo.host?.hostAddress ?: run {
                    onStatus("Resolved but no host address")
                    return
                }
                val port = serviceInfo.port
                onStatus("Found Mac at $host:$port — connecting…")
                connect(host, port)
            }
        })
    }

    private fun connect(host: String, port: Int) {
        val request = Request.Builder().url("ws://$host:$port").build()
        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                connected = true
                onStatus("Connected ✅  Copy text on your Mac.")
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                connected = false
                onStatus("Connection error: ${t.message}")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                connected = false
                onStatus("Disconnected")
            }
        })
    }

    private fun handleMessage(text: String) {
        try {
            val json = JSONObject(text)
            if (json.optString("type") == "clipboard_update") {
                onClipboardText(json.optString("text"))
            }
        } catch (e: Exception) {
            onStatus("Bad message: ${e.message}")
        }
    }

    fun stop() {
        webSocket?.close(1000, null)
        webSocket = null
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (_: Exception) {
            }
        }
        discoveryListener = null
    }
}
