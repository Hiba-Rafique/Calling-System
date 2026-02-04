package com.example.frontend

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat

class AppStateMonitorService : Service() {
    
    companion object {
        const val NOTIFICATION_ID = 3002
        const val CHANNEL_ID = "app_state_monitor"
        
        fun start(context: android.content.Context) {
            val intent = Intent(context, AppStateMonitorService::class.java)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
        
        fun stop(context: android.content.Context) {
            val intent = Intent(context, AppStateMonitorService::class.java)
            context.stopService(intent)
        }
    }
    
    private val handler = Handler(Looper.getMainLooper())
    private var monitorRunnable: Runnable? = null
    private var wasAppInForeground = true
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("APP_STATE", "🔧 AppStateMonitorService started")
        
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        startMonitoring()
        
        return START_STICKY
    }
    
    override fun onDestroy() {
        Log.d("APP_STATE", "🔧 AppStateMonitorService destroyed")
        stopMonitoring()
        super.onDestroy()
    }
    
    private fun createNotificationChannel() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID,
                "App State Monitor",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): android.app.Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App State Monitor")
            .setContentText("Monitoring app lifecycle")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }
    
    private fun startMonitoring() {
        monitorRunnable?.let { handler.removeCallbacks(it) }
        
        monitorRunnable = object : Runnable {
            override fun run() {
                try {
                    // Check if any activities are in foreground
                    val activityManager = getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                    val runningTasks = activityManager.getRunningTasks(1)
                    val isAppInForeground = runningTasks.isNotEmpty() && 
                        runningTasks[0].topActivity?.packageName == packageName
                    
                    Log.d("APP_STATE", "🔧 App in foreground: $isAppInForeground (was: $wasAppInForeground)")
                    
                    if (wasAppInForeground && !isAppInForeground) {
                        Log.d("APP_STATE", "🔧 App went to background - forcing socket disconnect")
                        // Send broadcast to notify Flutter app to disconnect socket
                        val intent = Intent("com.example.frontend.FORCE_DISCONNECT")
                        sendBroadcast(intent)
                    }
                    
                    wasAppInForeground = isAppInForeground
                    
                } catch (e: Exception) {
                    Log.e("APP_STATE", "🔧 Error monitoring app state", e)
                }
                
                // Check every 2 seconds
                handler.postDelayed(this, 2000)
            }
        }
        
        handler.post(monitorRunnable!!)
    }
    
    private fun stopMonitoring() {
        monitorRunnable?.let { handler.removeCallbacks(it) }
        monitorRunnable = null
    }
}
