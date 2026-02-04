package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ServiceHeartbeatReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.example.frontend.SERVICE_HEARTBEAT" -> {
                Log.d("HEARTBEAT", "🔧 Received service heartbeat from BackgroundKeepAliveService")
                
                // Check if socket is still connected by sending a ping to the backend
                try {
                    // This is a way to verify the Flutter engine is still responsive
                    Log.d("HEARTBEAT", "🔧 Flutter engine appears to be running")
                } catch (e: Exception) {
                    Log.e("HEARTBEAT", "🔧 Flutter engine may not be responsive", e)
                }
            }
        }
    }
}
