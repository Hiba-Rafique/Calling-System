package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("BOOT", "🔔 Boot receiver triggered: ${intent.action}")
        
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                Log.d("BOOT", "🔔 Starting background keep-alive service")
                // Start background keep-alive service
                BackgroundKeepAliveService.start(context)
                
                // Ensure Firebase Messaging service is ready
                try {
                    // This ensures Firebase Messaging can receive messages when app starts
                    val firebaseIntent = Intent(context, IncomingCallFirebaseService::class.java)
                    // We don't start the service here, but this ensures it's registered
                    Log.d("BOOT", "🔔 Firebase service registered")
                } catch (e: Exception) {
                    Log.e("BOOT", "❌ Failed to register Firebase service", e)
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Log.d("BOOT", "🔔 Android O+ detected, background services configured")
                }
            }
        }
    }
}
