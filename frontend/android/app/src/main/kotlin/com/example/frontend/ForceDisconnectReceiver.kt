package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ForceDisconnectReceiver : BroadcastReceiver() {
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("FORCE_DISCONNECT", "🔧 Force disconnect broadcast received")
        
        // Send a local notification to indicate disconnect
        try {
            val notificationManager = androidx.core.app.NotificationManagerCompat.from(context)
            val notification = androidx.core.app.NotificationCompat.Builder(context, "FORCE_DISCONNECT")
                .setContentTitle("Socket Disconnected")
                .setContentText("App went to background - forcing disconnect")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()
            
            notificationManager.notify(8888, notification)
        } catch (e: Exception) {
            Log.e("FORCE_DISCONNECT", "🔧 Failed to create notification", e)
        }
        
        // This will be handled by Flutter side through MethodChannel
        Log.d("FORCE_DISCONNECT", "🔧 Flutter should handle socket disconnect now")
    }
}
