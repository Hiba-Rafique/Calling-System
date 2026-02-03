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
import androidx.core.app.NotificationCompat

class CallRingingForegroundService : Service() {
  companion object {
    const val CHANNEL_ID = "incoming_call"
    const val NOTIF_ID = 2001

    const val EXTRA_CALL_ID = "call_id"
    const val EXTRA_FROM = "from"
    const val EXTRA_ROOM_ID = "room_id"
    const val EXTRA_IS_VIDEO = "is_video"

    const val ACTION_START = "com.example.frontend.ACTION_START_CALL_RINGING"
    const val ACTION_STOP = "com.example.frontend.ACTION_STOP_CALL_RINGING"
  }

  private val mainHandler = Handler(Looper.getMainLooper())
  private var timeoutRunnable: Runnable? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val action = intent?.action
    if (action == ACTION_STOP) {
      stopSelf()
      return START_NOT_STICKY
    }

    ensureChannel()

    val callId = intent?.getStringExtra(EXTRA_CALL_ID) ?: ""
    val from = intent?.getStringExtra(EXTRA_FROM) ?: "Unknown"
    val roomId = intent?.getStringExtra(EXTRA_ROOM_ID) ?: ""
    val isVideo = intent?.getBooleanExtra(EXTRA_IS_VIDEO, false) ?: false

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

    scheduleTimeout()

    return START_NOT_STICKY
  }

  override fun onDestroy() {
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
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val existing = manager.getNotificationChannel(CHANNEL_ID)
    if (existing != null) return

    val channel = NotificationChannel(
      CHANNEL_ID,
      "Incoming calls",
      NotificationManager.IMPORTANCE_HIGH
    )
    channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
    manager.createNotificationChannel(channel)
  }

  private fun buildIncomingCallNotification(
    callId: String,
    from: String,
    roomId: String,
    isVideo: Boolean
  ): Notification {
    val acceptIntent = Intent(this, IncomingCallActionReceiver::class.java).apply {
      action = IncomingCallActionReceiver.ACTION_ACCEPT
      putExtra(EXTRA_CALL_ID, callId)
      putExtra(EXTRA_FROM, from)
      putExtra(EXTRA_ROOM_ID, roomId)
      putExtra(EXTRA_IS_VIDEO, isVideo)
    }

    val declineIntent = Intent(this, IncomingCallActionReceiver::class.java).apply {
      action = IncomingCallActionReceiver.ACTION_DECLINE
      putExtra(EXTRA_CALL_ID, callId)
      putExtra(EXTRA_FROM, from)
      putExtra(EXTRA_ROOM_ID, roomId)
      putExtra(EXTRA_IS_VIDEO, isVideo)
    }

    val acceptPending = PendingIntent.getBroadcast(
      this,
      3001,
      acceptIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val declinePending = PendingIntent.getBroadcast(
      this,
      3002,
      declineIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    // Full-screen intent: launched ONLY after user interaction OR when the system decides it's allowed.
    // We still provide it so the notification can show as a call-style full-screen UI.
    val launchIntent = Intent(this, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
      action = IncomingCallActionReceiver.ACTION_OPEN_FROM_NOTIFICATION
      putExtra(EXTRA_CALL_ID, callId)
      putExtra(EXTRA_FROM, from)
      putExtra(EXTRA_ROOM_ID, roomId)
      putExtra(EXTRA_IS_VIDEO, isVideo)
    }

    val fullScreenPending = PendingIntent.getActivity(
      this,
      3003,
      launchIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val title = if (isVideo) "Incoming video call" else "Incoming voice call"

    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.sym_call_incoming)
      .setContentTitle(title)
      .setContentText(from)
      .setCategory(NotificationCompat.CATEGORY_CALL)
      .setPriority(NotificationCompat.PRIORITY_MAX)
      .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
      .setOngoing(true)
      .setAutoCancel(false)
      .setFullScreenIntent(fullScreenPending, true)
      .addAction(0, "Decline", declinePending)
      .addAction(0, "Accept", acceptPending)
      .build()
  }
}
