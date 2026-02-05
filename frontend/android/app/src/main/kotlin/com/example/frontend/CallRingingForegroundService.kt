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
import android.util.Log
import androidx.core.app.NotificationCompat

class CallRingingForegroundService : Service() {
  companion object {
    const val CHANNEL_ID = "incoming_call"
    const val NOTIF_ID = 2001

    const val EXTRA_CALL_ID = "call_id"
    const val EXTRA_FROM = "from"
    const val EXTRA_ROOM_ID = "room_id"
    const val EXTRA_IS_VIDEO = "is_video"

    const val ACTION_START = "START_RINGING"
    const val ACTION_STOP = "STOP_RINGING"
  }

  private var timeoutRunnable: Runnable? = null
  private val mainHandler = Handler(Looper.getMainLooper())

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.d("RINGING", "🔔 CallRingingForegroundService started")
    
    val action = intent?.action
    Log.d("RINGING", "🔔 Action: $action")
    
    // Handle backup keep-alive action
    if (action == "KEEP_ALIVE_BACKUP") {
        Log.d("RINGING", "🔔 Started as backup keep-alive service")
        ensureChannel()
        val notification = createKeepAliveNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID + 1000, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID + 1000, notification)
        }
        
        // Stop this backup service after 30 seconds
        Handler(Looper.getMainLooper()).postDelayed({
            Log.d("RINGING", "🔧 Stopping backup keep-alive service")
            stopSelf()
        }, 30000)
        
        return START_NOT_STICKY
    }
    
    if (action == ACTION_STOP) {
      Log.d("RINGING", "🔔 Stopping ringing service")
      stopSelf()
      return START_NOT_STICKY
    }

    ensureChannel()

    val callId = intent?.getStringExtra(EXTRA_CALL_ID) ?: ""
    val from = intent?.getStringExtra(EXTRA_FROM) ?: "Unknown"
    val roomId = intent?.getStringExtra(EXTRA_ROOM_ID) ?: ""
    val isVideo = intent?.getBooleanExtra(EXTRA_IS_VIDEO, false) ?: false

    Log.d("RINGING", "🔔 Call details - ID: $callId, From: $from, Room: $roomId, Video: $isVideo")

    val notification = buildIncomingCallNotification(callId, from, roomId, isVideo)

    if (Build.VERSION.SDK_INT >= 34) {
      startForeground(
        NOTIF_ID,
        notification,
        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
      )
    } else {
      startForeground(NOTIF_ID, notification)
    }

    Log.d("RINGING", "🔔 Foreground service started with notification")

    scheduleTimeout()

    return START_STICKY
  }

  override fun onDestroy() {
    Log.d("RINGING", "🔔 CallRingingForegroundService destroyed")
    timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
    timeoutRunnable = null
    super.onDestroy()
  }

  private fun scheduleTimeout() {
    timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
    timeoutRunnable = Runnable {
      stopSelf()
    }
    // Ringing window (30s). If you want WhatsApp-like longer windows, increase.
    mainHandler.postDelayed(timeoutRunnable!!, 30_000L)
  }

  private fun ensureChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        CHANNEL_ID,
        "Incoming Calls",
        NotificationManager.IMPORTANCE_HIGH
      ).apply {
        description = "Notifications for incoming calls"
        enableLights(true)
        enableVibration(true)
        vibrationPattern = longArrayOf(0, 1000, 500, 1000)
        setShowBadge(true)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
      }
      val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      manager.createNotificationChannel(channel)
    }
  }

  private fun buildIncomingCallNotification(
    callId: String,
    from: String,
    roomId: String,
    isVideo: Boolean
  ): Notification {
    val title = from // Just show the caller's name like WhatsApp
    val content = if (isVideo) "Incoming video call" else "Incoming voice call"
    
    // Create intent to open app with full call screen
    val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra("callId", callId)
        putExtra("from", from)
        putExtra("roomId", roomId)
        putExtra("isVideo", isVideo)
        putExtra("incomingCall", true)
        putExtra("showCallScreen", true) // Add flag to show full call screen
        putExtra("autoAnswer", false) // Don't auto-answer from notification tap
        action = "ANSWER_CALL"
    }
    
    val fullScreenPending = PendingIntent.getActivity(
      this, 0, fullScreenIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    
    // Accept intent - same as full screen intent but with autoAnswer
    val acceptIntent = Intent(this, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra("callId", callId)
        putExtra("from", from)
        putExtra("roomId", roomId)
        putExtra("isVideo", isVideo)
        putExtra("incomingCall", true)
        putExtra("showCallScreen", true) // Add flag to show full call screen
        putExtra("autoAnswer", true) // Auto-accept when Answer button is tapped
        action = "ANSWER_CALL"
    }
    
    val acceptPending = PendingIntent.getBroadcast(
      this, 1, acceptIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    
    // Decline intent
    val declineIntent = Intent(this, NotificationTapReceiver::class.java).apply {
        action = "OPEN_CALL_SCREEN"
        putExtra("callId", callId)
        putExtra("from", from)
        putExtra("roomId", roomId)
        putExtra("isVideo", isVideo)
        putExtra("incomingCall", true)
        putExtra("showCallScreen", true)
        putExtra("autoAnswer", false)
        putExtra("declineCall", true) // Add flag for decline
      }
    
    val declinePending = PendingIntent.getBroadcast(
      this, 2, declineIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // Also send a broadcast as backup
      val broadcastIntent = Intent(this, NotificationTapReceiver::class.java).apply {
        action = "OPEN_CALL_SCREEN"
        putExtra("callId", callId)
        putExtra("from", from)
        putExtra("roomId", roomId)
        putExtra("isVideo", isVideo)
        putExtra("incomingCall", true)
        putExtra("showCallScreen", true)
        putExtra("autoAnswer", false)
      }
      sendBroadcast(broadcastIntent)

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_menu_call)
      .setContentTitle(title)
      .setContentText(content)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_MAX)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setOngoing(true)
      .setAutoCancel(false)
      .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_LIGHTS) // Sound and lights
      .setVibrate(longArrayOf(0, 1000, 500, 1000)) // Explicit vibration pattern
      .setFullScreenIntent(fullScreenPending, true)
      .setContentIntent(fullScreenPending) // Open app when notification is tapped
      .setDeleteIntent(fullScreenPending) // Also open when notification is dismissed
      .setColor(0xFF4CAF50.toInt()) // WhatsApp green color
      .addAction(
        android.R.drawable.ic_menu_close_clear_cancel,
        "Decline",
        declinePending
      )
      .addAction(
        android.R.drawable.ic_menu_call,
        "Answer",
        acceptPending
      )
      .build()
  }
  
  private fun createKeepAliveNotification(): Notification {
    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setContentTitle("Service Active")
      .setContentText("Keeping calling service alive")
      .setSmallIcon(R.mipmap.ic_launcher)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setOngoing(true)
      .setSilent(true)
      .build()
  }
}