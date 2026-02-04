package com.example.frontend

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class IncomingCallFirebaseService : FirebaseMessagingService() {
    
    override fun onCreate() {
        super.onCreate()
        Log.d("FCM", "🔔 IncomingCallFirebaseService created")
    }
    
    override fun onMessageReceived(message: RemoteMessage) {
        Log.d("FCM", "🔔 FCM message received: ${message.data}")
        Log.d("FCM", "🔔 FCM notification: ${message.notification}")
        
        // Wake up the device immediately
        wakeUpDevice()
        
        // Disable debug notification for cleaner UX
        // try {
        //     val notificationManager = NotificationManagerCompat.from(this)
        //     val debugNotification = NotificationCompat.Builder(this, "DEBUG_FCM")
        //         .setContentTitle("FCM Received")
        //         .setContentText("Data: ${message.data}")
        //         .setSmallIcon(R.mipmap.ic_launcher)
        //         .setPriority(NotificationCompat.PRIORITY_HIGH)
        //         .setAutoCancel(true)
        //         .build()
        //     
        //     notificationManager.notify(9999, debugNotification)
        //     Log.d("FCM", "🔔 Debug notification shown")
        // } catch (e: Exception) {
        //     Log.e("FCM", "❌ Failed to create debug notification", e)
        // }
        
        val data = message.data
        val type = data["type"]
        Log.d("FCM", "🔔 Message type: $type")
        
        // Handle both data-only and notification messages
        if (type != "INCOMING_CALL") {
            // Check if this is a notification message that should trigger incoming call
            if (message.notification?.title == "Incoming Call") {
                Log.d("FCM", "🔔 Converting notification message to incoming call")
                // Convert notification to data format
                val modifiedData = mutableMapOf<String, String>()
                modifiedData.putAll(data)
                modifiedData["type"] = "INCOMING_CALL"
                handleIncomingCall(modifiedData)
            } else {
                Log.d("FCM", "🔔 Not an incoming call, ignoring")
                return
            }
        } else {
            handleIncomingCall(data)
        }
    }
    
    private fun wakeUpDevice() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "CallingSystem:FCMWakeLock"
            )
            
            wakeLock.acquire(5 * 1000L) // 5 seconds
            Log.d("FCM", "🔔 Device woken up for FCM")
        } catch (e: Exception) {
            Log.e("FCM", "❌ Failed to wake up device", e)
        }
    }
  
    private fun handleIncomingCall(data: Map<String, String>) {
    val callId = data["callId"] ?: (data["roomId"] ?: "")
    val from = data["callerId"] ?: data["from"] ?: "Unknown" // Handle both old and new field names
    val roomId = data["roomId"] ?: ""
    val isVideo = (data["isVideoCall"] ?: "false").lowercase() == "true"

    Log.d("FCM", "🔔 Starting ringing service for call: $callId from: $from")

    // Wake up the device immediately
    wakeUpDevice()

    // First, try to wake up the device
    try {
        val wakeUpIntent = Intent(this, WakeUpReceiver::class.java).apply {
            putExtra("callId", callId)
            putExtra("from", from)
            putExtra("roomId", roomId)
            putExtra("isVideo", isVideo)
            action = "WAKE_UP_FOR_CALL"
        }
        sendBroadcast(wakeUpIntent)
        Log.d("FCM", "🔔 Sent wake up broadcast")
    } catch (e: Exception) {
        Log.e("FCM", "❌ Failed to send wake up broadcast", e)
    }

    // Also directly start the ringing service
    try {
        val ringingIntent = Intent(this, CallRingingForegroundService::class.java).apply {
            action = CallRingingForegroundService.ACTION_START
            putExtra(CallRingingForegroundService.EXTRA_CALL_ID, callId)
            putExtra(CallRingingForegroundService.EXTRA_FROM, from)
            putExtra(CallRingingForegroundService.EXTRA_ROOM_ID, roomId)
            putExtra(CallRingingForegroundService.EXTRA_IS_VIDEO, isVideo)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(ringingIntent)
        } else {
            startService(ringingIntent)
        }
        
        Log.d("FCM", "🔔 Started ringing service directly")
    } catch (e: Exception) {
        Log.e("FCM", "❌ Failed to start ringing service", e)
    }
  }
    
    override fun onNewToken(token: String) {
        Log.d("FCM", "🔔 FCM token refreshed: $token")
        // You might want to send this to your backend
    }
}
