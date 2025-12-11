package com.musicassistant.music_assistant

import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val TAG = "EnsembleVolume"
    private val CHANNEL = "com.musicassistant.music_assistant/volume_buttons"
    private var methodChannel: MethodChannel? = null
    private var isListening = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Configuring Flutter engine, setting up MethodChannel")

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
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
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        Log.d(TAG, "onKeyDown: keyCode=$keyCode, isListening=$isListening")

        if (!isListening) {
            Log.d(TAG, "Not listening, passing to super")
            return super.onKeyDown(keyCode, event)
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                Log.d(TAG, "VOLUME UP pressed - sending to Flutter")
                methodChannel?.invokeMethod("volumeUp", null)
                true // Consume the event to prevent system volume change
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                Log.d(TAG, "VOLUME DOWN pressed - sending to Flutter")
                methodChannel?.invokeMethod("volumeDown", null)
                true // Consume the event to prevent system volume change
            }
            else -> {
                Log.d(TAG, "Other key, passing to super")
                super.onKeyDown(keyCode, event)
            }
        }
    }
}
