import 'package:flutter/services.dart';

class BackgroundKeepAlivePlatform {
  static const MethodChannel _channel = MethodChannel('com.example.frontend/background_service');

  static Future<void> startBackgroundService() async {
    try {
      await _channel.invokeMethod('startBackgroundService');
    } catch (e) {
      print('Failed to start background service: $e');
    }
  }

  static Future<void> stopBackgroundService() async {
    try {
      await _channel.invokeMethod('stopBackgroundService');
    } catch (e) {
      print('Failed to stop background service: $e');
    }
  }
}
