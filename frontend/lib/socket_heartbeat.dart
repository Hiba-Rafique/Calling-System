import 'dart:async';
import 'package:flutter/foundation.dart';
import 'call_service.dart';

class SocketHeartbeat {
  static final SocketHeartbeat _instance = SocketHeartbeat._internal();
  factory SocketHeartbeat() => _instance;
  SocketHeartbeat._internal();

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  int _missedBeats = 0;
  static const Duration _heartbeatInterval = Duration(seconds: 10);
  static const Duration _reconnectDelay = Duration(seconds: 5);

  void start() {
    stop();
    debugPrint('🔔 Starting socket heartbeat - interval: ${_heartbeatInterval.inSeconds}s');
    
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      _sendHeartbeat();
    });
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _missedBeats = 0;
    debugPrint('🔔 Stopped socket heartbeat');
  }

  void _sendHeartbeat() {
    try {
      final callService = CallService();
      if (callService.isDisposed) {
        debugPrint('🔔 CallService disposed, stopping heartbeat');
        stop();
        return;
      }
      
      // Check if socket is connected
      if (callService.socket != null && callService.socket!.connected) {
        callService.socket!.emit('heartbeat', {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'platform': 'mobile'
        });
        _isConnected = true;
        _missedBeats = 0;
        debugPrint('🔔 ❤️ Heartbeat sent - socket connected');
      } else {
        _missedBeats++;
        _isConnected = false;
        debugPrint('🔔 💔 Socket not connected (missed: $_missedBeats)');
        
        // Try to reconnect after 3 missed beats
        if (_missedBeats >= 3) {
          debugPrint('🔔 🔄 Attempting to reconnect socket...');
          _attemptReconnect();
        }
      }
    } catch (e) {
      _missedBeats++;
      _isConnected = false;
      debugPrint('🔔 ❌ Heartbeat failed: $e (missed: $_missedBeats)');
    }
  }

  void _attemptReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    
    _reconnectTimer = Timer(_reconnectDelay, () {
      try {
        final callService = CallService();
        if (!callService.isDisposed && callService.socket != null) {
          debugPrint('🔔 🔄 Reconnecting socket...');
          callService.socket!.connect();
          _missedBeats = 0;
        }
      } catch (e) {
        debugPrint('🔔 ❌ Reconnect failed: $e');
      }
    });
  }

  void onSocketConnected() {
    _isConnected = true;
    _missedBeats = 0;
    debugPrint('🔔 Socket connected - heartbeat active');
  }

  void onSocketDisconnected() {
    _isConnected = false;
    debugPrint('🔔 Socket disconnected - will try to reconnect');
  }
}
