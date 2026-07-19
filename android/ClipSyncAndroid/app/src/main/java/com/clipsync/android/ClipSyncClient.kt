package com.clipsync.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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
import java.util.concurrent.TimeUnit
import kotlin.random.Random

/**
 * Discovers the Mac (NSD), connects (WebSocket), handshakes (hello → session
 * key), and decrypts incoming clipboard updates.
 *
 * Reconnect strategy (Milestone A):
 *  - Cache the last resolved host:port and dial it first — near-instant reconnect
 *    after a Wi-Fi blip or Mac sleep/wake, skipping discovery entirely.
 *  - Fall back to NSD discovery (with a MulticastLock, since some devices filter
 *    multicast) if the cached dial fails or we have no cache.
 *  - Discovery is battery-expensive, so we run it only while reconnecting and
 *    stop it the moment we connect.
 *  - Backoff between attempts: 1s → 30s, doubling, with ±50% jitter.
 *
 * Callbacks fire on background threads; the caller hops to the main thread.
 */
class ClipSyncClient(
    private val context: Context,
    private val onStatus: (String) -> Unit,
    private val onClipboardText: (String) -> Unit
) {
    private val serviceType = "_clipsync._tcp."
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    // Ping the Mac every 15s. The Mac auto-replies pings, so a dead/gone server
    // fails a ping and OkHttp fires onFailure → reconnect. Without this, a silently
    // dead connection is never noticed (no data flowing = no error).
    private val httpClient = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .build()
    private val handler = Handler(Looper.getMainLooper())

    private val keypair = DeviceKeypair.generate()
    private val deviceId = UUID.randomUUID().toString()

    @Volatile private var running = false
    @Volatile private var session: SessionCrypto? = null
    @Volatile private var pendingSend: String? = null
    private var webSocket: WebSocket? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var reconnectAttempt = 0
    private var resolving = false
    private var lastHost: String? = null
    private var lastPort = 0
    private var discoveryTimeout: Runnable? = null

    fun start() {
        running = true
        reconnectAttempt = 0
        attemptConnect()
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        teardownSocket()
        stopDiscovery()
    }

    /**
     * Sends local clipboard text to the Mac (Android→Mac). If the secure channel
     * isn't up yet, the text is queued and flushed once the handshake completes
     * (and a cold start is kicked off) — so a tile tap works even when idle.
     */
    fun sendClipboard(text: String) {
        val active = session
        val socket = webSocket
        if (active != null && socket != null) {
            socket.send(buildUpdate(active, text))
        } else {
            pendingSend = text
            if (!running) start()
        }
    }

    private fun buildUpdate(active: SessionCrypto, text: String): String {
        val sealed = active.seal(text) // (nonce, ciphertext)
        return JSONObject().apply {
            put("type", "clipboard_update")
            put("eventId", UUID.randomUUID().toString())
            put("origin", deviceId)
            put("timestamp", System.currentTimeMillis() / 1000)
            put("mimeType", "text/plain")
            put("nonce", sealed.first)
            put("ciphertext", sealed.second)
        }.toString()
    }

    // MARK: - Connection lifecycle

    private fun attemptConnect() {
        if (!running) return
        val host = lastHost
        if (host != null) {
            onStatus("Reconnecting to your Mac…")
            connect(host, lastPort, fromCache = true)
        } else {
            startDiscovery()
        }
    }

    private fun scheduleReconnect() {
        if (!running) return
        val base = minOf(30_000L, 1_000L shl minOf(reconnectAttempt, 5)) // 1,2,4,8,16,30s
        val delay = (base * Random.nextDouble(0.5, 1.5)).toLong()
        reconnectAttempt++
        onStatus("Disconnected — retrying in ${delay / 1000}s")
        handler.postDelayed({ attemptConnect() }, delay)
    }

    private fun connect(host: String, port: Int, fromCache: Boolean) {
        teardownSocket()
        val request = Request.Builder().url("ws://$host:$port").build()
        webSocket = httpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                reconnectAttempt = 0
                lastHost = host
                lastPort = port
                stopDiscovery()
                onStatus("Connected — securing channel…")
                sendHello(webSocket)
            }

            override fun onMessage(webSocket: WebSocket, text: String) = handleMessage(text)

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                session = null
                if (!running) return
                if (fromCache) {
                    // Cached endpoint is stale (Mac got a new port / IP) — rediscover now.
                    lastHost = null
                    startDiscovery()
                } else {
                    scheduleReconnect()
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                session = null
                if (running) scheduleReconnect()
            }
        })
    }

    // MARK: - Discovery (only while reconnecting)

    private fun startDiscovery() {
        if (!running) return
        stopDiscovery()
        acquireMulticastLock()
        onStatus("Searching for your Mac…")
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("_clipsync") && session == null) resolve(service)
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                onStatus("Discovery failed (code $errorCode)")
                scheduleReconnect()
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        discoveryListener = listener
        nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, listener)

        // Bound each discovery burst so we don't leave mDNS running when the Mac is off.
        val timeout = Runnable {
            if (session == null && running) {
                stopDiscovery()
                scheduleReconnect()
            }
        }
        discoveryTimeout = timeout
        handler.postDelayed(timeout, 12_000)
    }

    private fun resolve(service: NsdServiceInfo) {
        if (resolving) return
        resolving = true
        nsdManager.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                resolving = false
            }
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                resolving = false
                val host = serviceInfo.host?.hostAddress ?: return
                lastHost = host
                lastPort = serviceInfo.port
                onStatus("Found Mac — connecting…")
                connect(host, serviceInfo.port, fromCache = false)
            }
        })
    }

    private fun stopDiscovery() {
        discoveryTimeout?.let { handler.removeCallbacks(it) }
        discoveryTimeout = null
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (_: Exception) {
            }
        }
        discoveryListener = null
        releaseMulticastLock()
    }

    private fun acquireMulticastLock() {
        if (multicastLock == null) {
            multicastLock = wifiManager.createMulticastLock("clipsync").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }

    // MARK: - Protocol

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
                    pendingSend?.let { queued -> pendingSend = null; sendClipboard(queued) }
                }
                "clipboard_update" -> decryptUpdate(json)?.let(onClipboardText)
            }
        } catch (e: Exception) {
            onStatus("Bad message: ${e.message}")
        }
    }

    private fun decryptUpdate(json: JSONObject): String? {
        if (json.has("ciphertext")) {
            val active = session ?: return null
            return active.open(json.getString("nonce"), json.getString("ciphertext"))
        }
        if (json.has("text")) return json.getString("text")
        return null
    }

    private fun teardownSocket() {
        webSocket?.close(1000, null)
        webSocket = null
    }
}
