package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.Context.MODE_PRIVATE
import android.os.Build
import androidx.core.content.ContextCompat

class IncomingCallActionReceiver : BroadcastReceiver() {
  companion object {
    const val ACTION_ACCEPT = "com.example.frontend.ACTION_ACCEPT_CALL"
    const val ACTION_DECLINE = "com.example.frontend.ACTION_DECLINE_CALL"
    const val ACTION_OPEN_FROM_NOTIFICATION = "com.example.frontend.ACTION_OPEN_FROM_NOTIFICATION"

    private const val PREFS = "incoming_call_prefs"
    private const val KEY_PENDING_ACCEPT = "pending_accept"
  }

  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      ACTION_ACCEPT -> {
        // Persist payload so Flutter can auto-accept once it starts and connects sockets.
        try {
          val prefs = context.getSharedPreferences(PREFS, MODE_PRIVATE)
          val b = intent.extras
          val callId = b?.getString(CallRingingForegroundService.EXTRA_CALL_ID) ?: ""
          val from = b?.getString(CallRingingForegroundService.EXTRA_FROM) ?: ""
          val roomId = b?.getString(CallRingingForegroundService.EXTRA_ROOM_ID) ?: ""
          val isVideo = b?.getBoolean(CallRingingForegroundService.EXTRA_IS_VIDEO, false) ?: false
          val json = """{\"callId\":\"$callId\",\"from\":\"$from\",\"roomId\":\"$roomId\",\"isVideoCall\":\"${if (isVideo) "true" else "false"}\",\"ts\":${System.currentTimeMillis()}}"""
          prefs.edit().putString(KEY_PENDING_ACCEPT, json).apply()
        } catch (_: Throwable) {}

        // User interaction => allowed to launch UI.
        val launch = Intent(context, MainActivity::class.java).apply {
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
          action = ACTION_OPEN_FROM_NOTIFICATION
          putExtras(intent.extras ?: return)
        }
        context.startActivity(launch)

        // Keep ringing foreground service alive (call setup will later stop/replace it).
      }

      ACTION_DECLINE -> {
        // Stop ringing service.
        val stopIntent = Intent(context, CallRingingForegroundService::class.java).apply {
          action = CallRingingForegroundService.ACTION_STOP
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          ContextCompat.startForegroundService(context, stopIntent)
        } else {
          context.startService(stopIntent)
        }
      }

      else -> {
        // no-op
      }
    }
  }
}
