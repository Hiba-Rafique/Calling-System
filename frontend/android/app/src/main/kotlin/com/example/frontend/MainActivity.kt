package com.example.frontend

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.frontend/media_projection"
    private val callChannelName = "com.example.frontend/call_ringing"
    private val backgroundChannelName = "com.example.frontend/background_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, MediaProjectionForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        val intent = Intent(this, MediaProjectionForegroundService::class.java)
                        stopService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRinging" -> {
                        val args = call.arguments as? Map<*, *>
                        val intent = Intent(this, CallRingingForegroundService::class.java).apply {
                            action = CallRingingForegroundService.ACTION_START
                            putExtra(CallRingingForegroundService.EXTRA_CALL_ID, (args?.get("callId") ?: "").toString())
                            putExtra(CallRingingForegroundService.EXTRA_FROM, (args?.get("from") ?: "Unknown").toString())
                            putExtra(CallRingingForegroundService.EXTRA_ROOM_ID, (args?.get("roomId") ?: "").toString())
                            val isVideoStr = (args?.get("isVideoCall") ?: "false").toString().lowercase()
                            putExtra(CallRingingForegroundService.EXTRA_IS_VIDEO, isVideoStr == "true")
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ContextCompat.startForegroundService(this, intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopRinging" -> {
                        val intent = Intent(this, CallRingingForegroundService::class.java).apply {
                            action = CallRingingForegroundService.ACTION_STOP
                        }
                        stopService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBackgroundService" -> {
                        BackgroundKeepAliveService.start(this)
                        AppStateMonitorService.start(this)
                        result.success(null)
                    }
                    "stopBackgroundService" -> {
                        BackgroundKeepAliveService.stop(this)
                        AppStateMonitorService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Start background keep-alive service when app starts
        BackgroundKeepAliveService.start(this)
        
        // Handle intent if app was opened from notification
        intent?.let { 
            Log.d("MainActivity", "Processing initial intent: ${it.action}")
            handleCallIntent(it) 
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("MainActivity", "Processing new intent: ${intent.action}")
        // Handle incoming call intents from notification taps
        handleCallIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        Log.d("MainActivity", "onResume")
        // Check for any pending call intents when app resumes
        intent?.let { handleCallIntent(it) }
    }

    private fun handleCallIntent(intent: Intent) {
        when (intent.action) {
            "ANSWER_CALL" -> {
                Log.d("MainActivity", "Handling ANSWER_CALL intent")
                // Forward call data to Flutter
                val callData = mapOf(
                    "callId" to (intent.getStringExtra("callId") ?: ""),
                    "from" to (intent.getStringExtra("from") ?: ""),
                    "roomId" to (intent.getStringExtra("roomId") ?: ""),
                    "isVideo" to (intent.getBooleanExtra("isVideo", false)),
                    "incomingCall" to (intent.getBooleanExtra("incomingCall", false)),
                    "showCallScreen" to (intent.getBooleanExtra("showCallScreen", false)),
                    "autoAnswer" to (intent.getBooleanExtra("autoAnswer", false))
                )
                
                // Send to Flutter via method channel
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "com.example.frontend/call_intent")
                        .invokeMethod("onCallIntent", callData)
                }
            }
        }
    }
}
