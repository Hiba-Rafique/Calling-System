import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class BackgroundCallService {
  static final BackgroundCallService _instance = BackgroundCallService._internal();
  factory BackgroundCallService() => _instance;
  BackgroundCallService._internal();

  static bool get isSupported => !kIsWeb;

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  IO.Socket? _backgroundSocket;
  Timer? _callTimeoutTimer;

  Future<void> initialize() async {
    if (kIsWeb) return;

    await _requestPermissions();
    await _initializeNotifications();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.notification.request();
  }

  Future<void> _initializeNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const init = InitializationSettings(android: androidInit);
    await _notifications.initialize(init);
  }

  void connectToServer(String userId, {required String serverUrl}) {
    if (kIsWeb) return;

    _backgroundSocket?.dispose();
    _backgroundSocket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _backgroundSocket!.on('connect', (_) {
      _backgroundSocket!.emit('register', userId);
    });

    _backgroundSocket!.on('incomingCall', (data) {
      final from = data['from']?.toString() ?? 'Unknown';
      _showIncomingCallNotification(from);
    });
  }

  Future<void> showCallConnectedNotification(String withUser) async {
    if (kIsWeb) return;

    const android = AndroidNotificationDetails(
      'calling_system_active',
      'Active Calls',
      channelDescription: 'Shows active call status',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );

    await _notifications.show(
      999,
      'Call Active',
      'Connected with $withUser',
      const NotificationDetails(android: android),
    );
  }

  Future<void> clearNotifications() async {
    if (kIsWeb) return;
    _callTimeoutTimer?.cancel();
    await _notifications.cancelAll();
  }

  Future<void> _showIncomingCallNotification(String from) async {
    const android = AndroidNotificationDetails(
      'calling_system_incoming',
      'Incoming Calls',
      channelDescription: 'Incoming call notifications',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
    );

    await _notifications.show(
      1000,
      'Incoming Call',
      'Call from $from',
      const NotificationDetails(android: android),
    );

    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
      clearNotifications();
    });
  }
}
