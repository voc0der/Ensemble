package com.musicassistant.music_assistant

import android.os.Handler
import android.os.Looper
import android.security.KeyChain
import android.security.KeyChainAliasCallback
import android.util.Log
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager

// Extend AudioServiceActivity instead of FlutterActivity to support audio_service package
// while also intercepting volume button events.
class MainActivity: AudioServiceActivity() {
    // ---------------- Volume button channel (existing behavior) ----------------
    private val TAG = "EnsembleVolume"
    private val VOLUME_CHANNEL = "com.musicassistant.music_assistant/volume_buttons"
    private var volumeChannel: MethodChannel? = null
    private var isListening = false

    // ---------------- Android KeyChain mTLS channel (new feature) ---------------
    private val MTLS_CHANNEL = "com.musicassistant.music_assistant/android_keychain"
    private var mtlsChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private data class WsSession(val client: OkHttpClient, val ws: WebSocket)
    private val wsSessions = mutableMapOf<String, WsSession>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Volume buttons channel
        Log.d(TAG, "Configuring Flutter engine, setting up volume MethodChannel")
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
        volumeChannel?.setMethodCallHandler { call, result ->
            Log.d(TAG, "Received method call: ${call.method}")
            when (call.method) {
                "startListening" -> {
                    isListening = true
                    Log.d(TAG, "Volume listening ENABLED")
                    result.success(null)
                }
                "stopListening" -> {
                    isListening = false
                    Log.d(TAG, "Volume listening DISABLED")
                    result.success(null)
                }
                else -> {
                    Log.d(TAG, "Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        // mTLS KeyChain channel
        mtlsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MTLS_CHANNEL)
        mtlsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "selectClientCertificate" -> {
                    val host = call.argument<String>("host")
                    val port = call.argument<Int>("port")
                    selectAlias(host, port, result)
                }
                "getCertificateSubject" -> {
                    val alias = call.argument<String>("alias")
                    if (alias.isNullOrBlank()) {
                        result.success(null)
                    } else {
                        Thread {
                            try {
                                val chain = KeyChain.getCertificateChain(this, alias)
                                val subj = chain?.firstOrNull()?.subjectX500Principal?.name
                                mainHandler.post { result.success(subj) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("CERT_INFO", e.message, null) }
                            }
                        }.start()
                    }
                }
                "wsConnect" -> {
                    wsConnect(call, result)
                }
                "wsSend" -> {
                    val id = call.argument<String>("id")
                    val message = call.argument<String>("message")
                    if (id.isNullOrBlank() || message == null) {
                        result.error("BAD_ARGS", "Missing id/message", null)
                        return@setMethodCallHandler
                    }
                    val session = wsSessions[id]
                    if (session == null) {
                        result.error("NO_SESSION", "No WebSocket session for id=$id", null)
                        return@setMethodCallHandler
                    }
                    session.ws.send(message)
                    result.success(null)
                }
                "wsClose" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) {
                        result.error("BAD_ARGS", "Missing id", null)
                        return@setMethodCallHandler
                    }
                    val code = call.argument<Int>("code") ?: 1000
                    val reason = call.argument<String>("reason") ?: ""
                    val session = wsSessions[id]
                    if (session != null) {
                        session.ws.close(code, reason)
                        wsSessions.remove(id)
                    }
                    result.success(null)
                }
                "httpRequest" -> {
                    httpRequest(call, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun selectAlias(host: String?, port: Int?, result: MethodChannel.Result) {
        val callback = KeyChainAliasCallback { alias ->
            mainHandler.post { result.success(alias) }
        }

        // keyTypes: allow both RSA and EC.
        val keyTypes = arrayOf("RSA", "EC")
        val issuers: Array<java.security.Principal>? = null

        try {
            KeyChain.choosePrivateKeyAlias(
                this,
                callback,
                keyTypes,
                issuers,
                host,
                port ?: -1,
                null
            )
        } catch (e: Exception) {
            result.error("KEYCHAIN", e.message, null)
        }
    }

    private fun wsConnect(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val alias = call.argument<String>("alias")
        val url = call.argument<String>("url")
        @Suppress("UNCHECKED_CAST")
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()

        if (alias.isNullOrBlank()) {
            result.error("NO_ALIAS", "No KeyChain alias provided", null)
            return
        }
        if (url.isNullOrBlank()) {
            result.error("NO_URL", "No URL provided", null)
            return
        }

        // Build OkHttp client with KeyChain client cert
        val client = buildOkHttpClient(alias)

        val requestBuilder = Request.Builder().url(url)
        for ((k, v) in headers) {
            requestBuilder.addHeader(k, v)
        }
        val request = requestBuilder.build()

        val id = UUID.randomUUID().toString()

        val listener = object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                emitWsEvent(id, "open", mapOf(
                    "code" to response.code,
                    "reason" to response.message
                ))
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                emitWsEvent(id, "message", mapOf(
                    "message" to text
                ))
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                emitWsEvent(id, "closing", mapOf(
                    "code" to code,
                    "reason" to reason
                ))
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                emitWsEvent(id, "closed", mapOf(
                    "code" to code,
                    "reason" to reason
                ))
                wsSessions.remove(id)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val msg = t.message ?: t.javaClass.simpleName
                emitWsEvent(id, "failure", mapOf(
                    "error" to msg,
                    "httpCode" to (response?.code ?: -1),
                    "httpReason" to (response?.message ?: "")
                ))
                wsSessions.remove(id)
            }
        }

        val ws = client.newWebSocket(request, listener)
        wsSessions[id] = WsSession(client, ws)

        result.success(id)
    }

    private fun emitWsEvent(id: String, type: String, extra: Map<String, Any?>) {
        val chan = mtlsChannel ?: return
        val payload = HashMap<String, Any?>()
        payload["id"] = id
        payload["type"] = type
        for ((k, v) in extra) {
            payload[k] = v
        }
        mainHandler.post {
            try {
                chan.invokeMethod("wsEvent", payload)
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    private fun buildOkHttpClient(alias: String): OkHttpClient {
        // Trust-all (matches paperless-mobile approach). This is convenient for self-signed
        // setups, but you can tighten it later if desired.
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val trustManager = trustAllCerts[0] as X509TrustManager

        val keyManager: X509KeyManager = object : X509KeyManager {
            override fun getClientAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String> = arrayOf(alias)
            override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?): String = alias
            override fun getServerAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String>? = null
            override fun chooseServerAlias(keyType: String?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?): String? = null

            override fun getCertificateChain(aliasRequested: String?): Array<X509Certificate>? {
                val a = aliasRequested ?: alias
                val chain = KeyChain.getCertificateChain(this@MainActivity, a) ?: return null
                @Suppress("UNCHECKED_CAST")
                return chain as Array<X509Certificate>
            }

            override fun getPrivateKey(aliasRequested: String?): java.security.PrivateKey? {
                val a = aliasRequested ?: alias
                return KeyChain.getPrivateKey(this@MainActivity, a)
            }
        }

        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(arrayOf<KeyManager>(keyManager), trustAllCerts, SecureRandom())
        val sslSocketFactory: SSLSocketFactory = sslContext.socketFactory

        val verifier = HostnameVerifier { _, _ -> true }

        return OkHttpClient.Builder()
            .sslSocketFactory(sslSocketFactory, trustManager)
            .hostnameVerifier(verifier)
            // WebSocket should not time out reads. Use ping to keep NATs happy.
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .pingInterval(30, TimeUnit.SECONDS)
            .build()
    }

    private fun httpRequest(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val alias = call.argument<String>("alias")
        val method = call.argument<String>("method")
        val url = call.argument<String>("url")
        @Suppress("UNCHECKED_CAST")
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        val body = call.argument<String>("body")

        if (alias.isNullOrBlank() || method.isNullOrBlank() || url.isNullOrBlank()) {
            result.error("BAD_ARGS", "Missing required arguments", null)
            return
        }

        Thread {
            try {
                val client = buildOkHttpClient(alias)
                val requestBuilder = Request.Builder().url(url)

                // Add headers
                for ((k, v) in headers) {
                    requestBuilder.addHeader(k, v)
                }

                // Add body for POST/PUT/PATCH
                if (!body.isNullOrBlank() && (method == "POST" || method == "PUT" || method == "PATCH")) {
                    val mediaType = "application/json; charset=utf-8".toMediaType()
                    requestBuilder.method(method, body.toRequestBody(mediaType))
                } else {
                    requestBuilder.method(method, null)
                }

                val request = requestBuilder.build()
                val response = client.newCall(request).execute()

                val responseHeaders = mutableMapOf<String, String>()
                for (name in response.headers.names()) {
                    // Get all values for this header (important for Set-Cookie which can have multiple values)
                    val values = response.headers.values(name)
                    responseHeaders[name] = if (values.size > 1) {
                        values.joinToString(", ")
                    } else {
                        values.firstOrNull() ?: ""
                    }
                }

                val responseBody = response.body?.string() ?: ""

                val responseMap = mapOf(
                    "statusCode" to response.code,
                    "headers" to responseHeaders,
                    "body" to responseBody
                )

                mainHandler.post { result.success(responseMap) }
            } catch (e: Exception) {
                mainHandler.post { result.error("HTTP_ERROR", e.message, null) }
            }
        }.start()
    }

    // Use dispatchKeyEvent instead of onKeyDown - Flutter's engine uses dispatchKeyEvent
    // and may consume events before they reach onKeyDown
    override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) {
            return super.dispatchKeyEvent(event)
        }

        val keyCode = event.keyCode
        val action = event.action

        Log.d(TAG, "dispatchKeyEvent: keyCode=$keyCode, action=$action, isListening=$isListening")

        // Only handle KEY_DOWN events to avoid double-triggering (down + up)
        if (action != KeyEvent.ACTION_DOWN) {
            // For volume keys when listening, also consume ACTION_UP to fully block system volume
            if (isListening && (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
                Log.d(TAG, "Consuming ACTION_UP for volume key")
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        if (!isListening) {
            Log.d(TAG, "Not listening, passing to super")
            return super.dispatchKeyEvent(event)
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                Log.d(TAG, "VOLUME UP pressed - sending to Flutter")
                volumeChannel?.invokeMethod("volumeUp", null)
                true // Consume the event to prevent system volume change
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d(TAG, "VOLUME DOWN pressed - sending to Flutter")
                volumeChannel?.invokeMethod("volumeDown", null)
                true // Consume the event to prevent system volume change
            }
            else -> {
                Log.d(TAG, "Other key, passing to super")
                super.dispatchKeyEvent(event)
            }
        }
    }
}
