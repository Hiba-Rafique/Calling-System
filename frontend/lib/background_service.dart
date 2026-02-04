import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:background_fetch/background_fetch.dart' as background_fetch;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'call_service.dart';
import 'background_keep_alive_platform.dart';

// Background fetch callback
@pragma('vm:entry-point')
void backgroundFetchHeadlessTask(background_fetch.HeadlessTask task) async {
  try {
    debugPrint('🔄 Background fetch headless task: ${task.taskId}');
    // Perform minimal work to keep app alive
    // Don't do heavy network operations here
    background_fetch.BackgroundFetch.finish(task.taskId);
  } catch (e) {
    debugPrint('🔄 Background fetch failed: $e');
    background_fetch.BackgroundFetch.finish(task.taskId);
  }
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request critical permissions
      await _requestPermissions();
      
      // Initialize notifications
      await _initializeNotifications();
      
      // Initialize background fetch
      await _initializeBackgroundFetch();
      
      _isInitialized = true;
      debugPrint('🟢 BackgroundService initialized');
    } catch (e) {
      debugPrint('🔴 BackgroundService initialization failed: $e');
    }
  }

  Future<void> _requestPermissions() async {
    // Request ignore battery optimizations
    if (await Permission.ignoreBatteryOptimizations.status.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    // Request system alert window
    if (await Permission.systemAlertWindow.status.isDenied) {
      await Permission.systemAlertWindow.request();
    }

    // Request notification permission (Android 13+)
    if (await Permission.notification.status.isDenied) {
      await Permission.notification.request();
    }

    debugPrint('🔐 Background permissions requested');
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channel for background service
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'background_service',
      'Background Service',
      description: 'Keeps the calling service running in background',
      importance: Importance.low,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    debugPrint('🔔 Background notifications initialized');
  }

  Future<void> _initializeBackgroundFetch() async {
    try {
      await background_fetch.BackgroundFetch.configure(
        background_fetch.BackgroundFetchConfig(
          minimumFetchInterval: 15, // minutes
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          requiredNetworkType: background_fetch.NetworkType.NONE,
        ),
        backgroundFetchHeadlessTask,
      );

      await background_fetch.BackgroundFetch.registerHeadlessTask(backgroundFetchHeadlessTask);
      debugPrint('🔄 Background fetch configured');
    } catch (e) {
      debugPrint('🔴 Background fetch configuration failed: $e');
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('🔔 Background notification tapped: ${response.payload}');
    // Handle notification tap if needed
  }

  Future<void> showBackgroundNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'background_service',
      'Background Service',
      channelDescription: 'Keeps the calling service running in background',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  Future<void> startBackgroundService() async {
    try {
      // Start native background keep-alive service
      await BackgroundKeepAlivePlatform.startBackgroundService();
      
      // Show persistent notification
      await showBackgroundNotification(
        'Calling Service Active',
        'Ready to receive incoming calls',
      );

      // Start background fetch
      await background_fetch.BackgroundFetch.start();

      debugPrint('🟢 Background service started');
    } catch (e) {
      debugPrint('🔴 Failed to start background service: $e');
    }
  }

  Future<void> stopBackgroundService() async {
    try {
      // Stop native background keep-alive service
      await BackgroundKeepAlivePlatform.stopBackgroundService();
      
      // Stop background fetch
      await background_fetch.BackgroundFetch.stop();

      // Cancel notifications
      await _notifications.cancel(0);

      debugPrint('🟡 Background service stopped');
    } catch (e) {
      debugPrint('🔴 Failed to stop background service: $e');
    }
  }
}
