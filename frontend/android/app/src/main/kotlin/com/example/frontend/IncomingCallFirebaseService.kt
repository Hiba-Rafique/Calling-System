package com.example.frontend

import android.content.Intent
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import androidx.core.content.ContextCompat

class IncomingCallFirebaseService : FirebaseMessagingService() {
  override fun onMessageReceived(message: RemoteMessage) {
    val data = message.data
    val type = data["type"]
    if (type != "INCOMING_CALL") {
      return
    }

    val callId = data["callId"] ?: (data["roomId"] ?: "")
    val from = data["from"] ?: "Unknown"
    val roomId = data["roomId"] ?: ""
    val isVideo = (data["isVideoCall"] ?: "false").lowercase() == "true"

    val intent = Intent(this, CallRingingForegroundService::class.java).apply {
      action = CallRingingForegroundService.ACTION_START
      putExtra(CallRingingForegroundService.EXTRA_CALL_ID, callId)
      putExtra(CallRingingForegroundService.EXTRA_FROM, from)
      putExtra(CallRingingForegroundService.EXTRA_ROOM_ID, roomId)
      putExtra(CallRingingForegroundService.EXTRA_IS_VIDEO, isVideo)
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      ContextCompat.startForegroundService(this, intent)
    } else {
      startService(intent)
    }
  }
}
