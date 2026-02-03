import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallRingingPlatform {
  static const MethodChannel _ch = MethodChannel('com.example.frontend/call_ringing');

  static Future<void> stopRinging() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod('stopRinging');
    } catch (_) {}
  }

  static Future<void> startRinging(Map<String, dynamic> payload) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _ch.invokeMethod('startRinging', payload);
    } catch (_) {}
  }
}
