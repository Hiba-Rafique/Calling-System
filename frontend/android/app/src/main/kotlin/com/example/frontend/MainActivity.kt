package com.example.frontend

import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.frontend/media_projection"
    private val callChannelName = "com.example.frontend/call_ringing"

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
    }
}
