package com.example.frontend

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class NotificationTapReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("NotificationTapReceiver", "Received broadcast: ${intent?.action}")
        
        when (intent?.action) {
            "OPEN_CALL_SCREEN" -> {
                Log.d("NotificationTapReceiver", "Opening call screen from broadcast")
                val callIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("callId", intent?.getStringExtra("callId") ?: "")
                    putExtra("from", intent?.getStringExtra("from") ?: "")
                    putExtra("roomId", intent?.getStringExtra("roomId") ?: "")
                    putExtra("isVideo", intent?.getBooleanExtra("isVideo", false))
                    putExtra("incomingCall", true)
                    putExtra("showCallScreen", true)
                    putExtra("autoAnswer", intent?.getBooleanExtra("autoAnswer", false))
                    putExtra("declineCall", intent?.getBooleanExtra("declineCall", false))
                    action = "ANSWER_CALL"
                }
                
                context?.startActivity(callIntent)
            }
        }
    }
}
