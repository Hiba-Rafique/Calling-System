package com.example.frontend

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import android.util.Log

class BackgroundKeepAliveService : Service() {
    
    companion object {
        const val NOTIFICATION_ID = 3001
        const val CHANNEL_ID = "background_keep_alive"
        
        fun start(context: Context) {
            val intent = Intent(context, BackgroundKeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d("KEEP_ALIVE", "🔧 BackgroundKeepAliveService start called")
        }
        
        fun stop(context: Context) {
            val intent = Intent(context, BackgroundKeepAliveService::class.java)
            context.stopService(intent)
            Log.d("KEEP_ALIVE", "🔧 BackgroundKeepAliveService stop called")
        }
    }
    
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var heartbeatRunnable: Runnable? = null
    
    override fun onCreate() {
        super.onCreate()
        Log.d("KEEP_ALIVE", "🔧 BackgroundKeepAliveService created")
        createNotificationChannel()
        acquireWakeLock()
        startHeartbeat()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("KEEP_ALIVE", "🔧 BackgroundKeepAliveService started")
        
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        
        // Restart heartbeat if needed
        if (heartbeatRunnable == null) {
            startHeartbeat()
        }
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onDestroy() {
        Log.d("KEEP_ALIVE", "🔧 BackgroundKeepAliveService destroyed")
        stopHeartbeat()
        releaseWakeLock()
        super.onDestroy()
    }
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d("KEEP_ALIVE", "🔧 BackgroundKeepAliveService task removed - APP WAS KILLED")
        Log.d("KEEP_ALIVE", "🔧 Restarting service to keep app alive...")
        
        // Restart service if task is removed - this keeps the process alive
        val restartServiceIntent = Intent(applicationContext, BackgroundKeepAliveService::class.java)
        restartServiceIntent.setPackage(packageName)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(restartServiceIntent)
        } else {
            startService(restartServiceIntent)
        }
        
        // Also start the ringing service as a backup to ensure something stays alive
        try {
            val ringingIntent = Intent(applicationContext, CallRingingForegroundService::class.java)
            ringingIntent.action = "KEEP_ALIVE_BACKUP"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(ringingIntent)
            } else {
                startService(ringingIntent)
            }
            Log.d("KEEP_ALIVE", "🔧 Started backup ringing service")
        } catch (e: Exception) {
            Log.e("KEEP_ALIVE", "🔧 Failed to start backup service", e)
        }
        
        super.onTaskRemoved(rootIntent)
    }
    
    private fun startHeartbeat() {
        stopHeartbeat()
        
        heartbeatRunnable = object : Runnable {
            override fun run() {
                Log.d("KEEP_ALIVE", "🔧 Background service heartbeat - app process is alive")
                
                // Check if we can still access the Flutter engine
                try {
                    // Send a broadcast to Flutter to check if it's alive
                    val intent = Intent("com.example.frontend.SERVICE_HEARTBEAT")
                    sendBroadcast(intent)
                } catch (e: Exception) {
                    Log.e("KEEP_ALIVE", "🔧 Error sending heartbeat", e)
                }
                
                // Send heartbeat every 30 seconds
                handler.postDelayed(this, 30000)
            }
        }
        
        handler.post(heartbeatRunnable!!)
        Log.d("KEEP_ALIVE", "🔧 Background service heartbeat started")
    }
    
    private fun stopHeartbeat() {
        heartbeatRunnable?.let { handler.removeCallbacks(it) }
        heartbeatRunnable = null
        Log.d("KEEP_ALIVE", "🔧 Background service heartbeat stopped")
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background Keep Alive",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the calling service running in background"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
            Log.d("KEEP_ALIVE", "🔧 Notification channel created")
        }
    }
    
    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Calling Service Active")
            .setContentText("Ready to receive incoming calls")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }
    
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CallingSystem:BackgroundKeepAlive"
            ).apply {
                acquire(10 * 60 * 1000L) // 10 minutes
            }
            Log.d("KEEP_ALIVE", "🔧 Wake lock acquired")
        } catch (e: Exception) {
            Log.e("KEEP_ALIVE", "🔧 Failed to acquire wake lock", e)
        }
    }
    
    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d("KEEP_ALIVE", "🔧 Wake lock released")
            }
        }
        wakeLock = null
    }
}
