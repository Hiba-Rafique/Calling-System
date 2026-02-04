package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

class WakeUpReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("WAKEUP", "🔔 WakeUpReceiver triggered")
        
        try {
            // Acquire wake lock to wake up device
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "CallingSystem:IncomingCallWakeLock"
            )
            
            wakeLock.acquire(10 * 1000L) // 10 seconds
            
            Log.d("WAKEUP", "🔔 Wake lock acquired")
            
            // Start the ringing service
            val callId = intent.getStringExtra("callId") ?: ""
            val from = intent.getStringExtra("from") ?: "Unknown"
            val roomId = intent.getStringExtra("roomId") ?: ""
            val isVideo = intent.getBooleanExtra("isVideo", false)
            
            val ringingIntent = Intent(context, CallRingingForegroundService::class.java).apply {
                action = CallRingingForegroundService.ACTION_START
                putExtra(CallRingingForegroundService.EXTRA_CALL_ID, callId)
                putExtra(CallRingingForegroundService.EXTRA_FROM, from)
                putExtra(CallRingingForegroundService.EXTRA_ROOM_ID, roomId)
                putExtra(CallRingingForegroundService.EXTRA_IS_VIDEO, isVideo)
            }
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(ringingIntent)
            } else {
                context.startService(ringingIntent)
            }
            
            Log.d("WAKEUP", "🔔 Started ringing service from WakeUpReceiver")
            
        } catch (e: Exception) {
            Log.e("WAKEUP", "❌ Failed to wake up device", e)
        }
    }
}
