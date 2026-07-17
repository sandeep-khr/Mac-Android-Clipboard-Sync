package com.clipsync.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import com.clipsync.android.crypto.DeviceKeypair
import com.clipsync.android.crypto.SessionCrypto
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.Base64
import java.util.UUID

/**
 * The receiver:
 *  1. discover the Mac via NSD (`_clipsync._tcp`)
 *  2. connect over WebSocket
 *  3. `hello` handshake — exchange public keys, derive the session key
 *  4. decrypt each encrypted `clipboard_update` and hand the text to the UI
 *
 * Identity keys are ephemeral for now (no pairing gate / Keystore persistence
 * yet). Callbacks fire on background threads; the UI layer hops to the main
 * thread.
 */
class ClipSyncClient(
    context: Context,
    private val onStatus: (String) -> Unit,
    private val onClipboardText: (String) -> Unit
) {
    private val serviceType = "_clipsync._tcp."
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val httpClient = OkHttpClient()

    private val keypair = DeviceKeypair.generate()
    private val deviceId = UUID.randomUUID().toString()
    private var session: SessionCrypto? = null

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
                onStatus("Connected — securing channel…")
                sendHello(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                connected = false
                session = null
                onStatus("Connection error: ${t.message}")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                connected = false
                session = null
                onStatus("Disconnected")
            }
        })
    }

    /** Sends our `hello` (public key) so both sides can derive the session key. */
    private fun sendHello(webSocket: WebSocket) {
        val hello = JSONObject().apply {
            put("type", "hello")
            put("deviceId", deviceId)
            put("deviceName", Build.MODEL ?: "Android")
            put("publicKey", keypair.publicKeyBase64)
            put("protocolVersion", 1)
        }
        webSocket.send(hello.toString())
    }

    private fun handleMessage(text: String) {
        try {
            val json = JSONObject(text)
            when (json.optString("type")) {
                "hello" -> {
                    val peerPublicKey = Base64.getDecoder().decode(json.getString("publicKey"))
                    session = SessionCrypto(keypair, peerPublicKey)
                    onStatus("Connected ✅  Copy text on your Mac.")
                }
                "clipboard_update" -> {
                    val plaintext = decryptUpdate(json)
                    if (plaintext != null) onClipboardText(plaintext)
                }
            }
        } catch (e: Exception) {
            onStatus("Bad message: ${e.message}")
        }
    }

    /** Decrypts an encrypted `clipboard_update`; falls back to plaintext `text`. */
    private fun decryptUpdate(json: JSONObject): String? {
        if (json.has("ciphertext")) {
            val active = session ?: run {
                onStatus("Received an update before the secure channel was ready")
                return null
            }
            return active.open(json.getString("nonce"), json.getString("ciphertext"))
        }
        // Backward-compat with the plaintext spike.
        if (json.has("text")) return json.getString("text")
        return null
    }

    fun stop() {
        webSocket?.close(1000, null)
        webSocket = null
        session = null
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (_: Exception) {
            }
        }
        discoveryListener = null
    }
}
