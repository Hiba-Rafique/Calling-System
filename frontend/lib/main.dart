import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:background_fetch/background_fetch.dart';
import 'callkit_bridge.dart';
import 'auth_screen.dart';
import 'auth_service.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';
import 'call_service.dart';
import 'background_call_service.dart';
import 'background_service.dart';
import 'set_call_id_screen.dart';
import 'pending_call_accept.dart';
import 'socket_heartbeat.dart';
import 'background_keep_alive_platform.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String _incomingCallChannelId = 'incoming_calls';
const String _incomingCallChannelName = 'Incoming calls';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);

  await _localNotifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint('[LOCAL_NOTIF] actionId=${response.actionId} payload=${response.payload}');
      // TODO: Wire these actions into your real call accept/decline flow.
      // For data-only pushes, the backend should include enough info in payload
      // (roomId/callerId/etc.) so you can start signaling when user accepts.
      if (response.actionId == 'ACCEPT_CALL') {
        debugPrint('[CALL_UI] Accept tapped');
      } else if (response.actionId == 'DECLINE_CALL') {
        debugPrint('[CALL_UI] Decline tapped');
      } else {
        debugPrint('[CALL_UI] Notification tapped');
      }
    },
  );

  final android = _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) {
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _incomingCallChannelId,
        _incomingCallChannelName,
        description: 'Full-screen incoming call alerts',
        importance: Importance.max,
      ),
    );
  }
}

/// IMPORTANT: Top-level FCM background handler.
///
/// - Must be a top-level function (not inside a class).
/// - Must be annotated as an entry-point so it can run in a background isolate.
/// - Handles **data-only** messages when the app is in background/killed.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Required so plugins (e.g. local notifications) can be used in the background isolate.
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  debugPrint('[FCM][background] messageId=${message.messageId} data=${message.data}');

  final type = message.data['type']?.toString();
  if (type == 'INCOMING_CALL') {
    showIncomingCallUI(message.data);
  }
}

/// Placeholder for WhatsApp-style incoming call UI.
///
/// For Android reliability, this should eventually be backed by a full-screen
/// notification + a foreground service (or native ConnectionService) to wake and
/// present UI even under Doze/background restrictions.
void showIncomingCallUI(Map<String, dynamic> data) {
  debugPrint('[CALL_UI] showIncomingCallUI payload=$data');

  // Production-grade incoming call UI on Android:
  // Use CallKit-style UX (full-screen call notification + lock-screen UI).
  // This is triggered from:
  // - foreground FCM
  // - background FCM (top-level handler)
  // - killed-state initial message
  _showCallkitIncoming(data);
}

Future<void> _showCallkitIncoming(Map<String, dynamic> data) async {
  if (kIsWeb) return;
  try {
    final callId = (data['callId'] ?? data['call_id'] ?? data['roomId'] ?? '').toString();
    if (callId.isEmpty) {
      debugPrint('[CALLKIT] missing callId in payload; not showing UI');
      return;
    }

    final callerName = (data['callerName'] ?? data['from'] ?? 'Unknown').toString();
    final callType = (data['callType'] ?? (data['isVideoCall'] == 'true' ? 'video' : 'audio')).toString();

    final params = <String, dynamic>{
      'id': callId,
      'nameCaller': callerName,
      'appName': 'Calling System',
      'avatar': '',
      'handle': callerName,
      'type': (callType.toLowerCase().contains('video')) ? 1 : 0,
      'duration': 30000,
      'textAccept': 'Accept',
      'textDecline': 'Decline',
      'extra': {
        // Preserve the original payload so Accept can proceed to call setup.
        ...data,
      },
      'android': {
        'isCustomNotification': true,
        'isShowLogo': false,
        'isShowCallback': false,
        'isShowMissedCallNotification': true,
        'ringtonePath': 'system_ringtone_default',
        'backgroundColor': '#095E54',
        'actionColor': '#4CAF50',
        'incomingCallNotificationChannelName': 'Incoming Calls',
      },
    };

    await CallkitBridge.showIncoming(params);
    debugPrint('[CALLKIT] showCallkitIncoming shown for callId=$callId');
  } catch (e) {
    debugPrint('[CALLKIT] failed to show incoming UI: $e');
    // Fallback to local notification if CallKit fails for any reason.
    _showIncomingCallNotification(data);
  }
}

Future<void> _endCallkit(String callId) async {
  try {
    await CallkitBridge.endCall(callId);
  } catch (_) {}
}

void _setupCallkitEventHandlers() {
  if (kIsWeb) return;

  CallkitBridge.onEvent.listen((event) async {
    final dynamic eventName = (event is Map) ? event['event'] : (event?.event);
    final dynamic body = (event is Map) ? event['body'] : (event?.body);
    debugPrint('[CALLKIT] event=$eventName body=$body');

    final callId = body is Map ? (body['id'] ?? body['callId'] ?? body['uuid'])?.toString() : null;

    final e = eventName?.toString();
    if (e == 'ACTION_CALL_ACCEPT' || e == 'ACTION_CALL_ACCEPTED' || e == 'accept') {
      // Hard requirement:
      // - Launch app
      // - Start a foreground service
      // - Proceed to call setup (placeholder)
      // NOTE: do NOT attempt to open UI directly from background without a notification.

      // Placeholder: show an active call notification (foreground-like) using existing service.
      // Your real implementation should start an Android foreground service that maintains
      // call state and audio routing.
      try {
        await BackgroundCallService().showCallConnectedNotification(
          (body is Map ? (body['nameCaller']?.toString() ?? 'Unknown') : 'Unknown'),
        );
      } catch (_) {}

      debugPrint('[CALLKIT] ACCEPT: proceed to call setup (placeholder)');
    }

    if (e == 'ACTION_CALL_DECLINE' || e == 'ACTION_CALL_DECLINED' || e == 'decline') {
      if (callId != null) {
        await _endCallkit(callId);
      }
      debugPrint('[CALLKIT] DECLINE: notify backend (placeholder)');
      // TODO: call your backend endpoint to decline the call (requires auth + callId)
      // e.g. POST /api/calls/decline { callId }
    }

    if (e == 'ACTION_CALL_ENDED' || e == 'ACTION_CALL_TIMEOUT' || e == 'ended' || e == 'timeout') {
      // Cleanup any foreground notification.
      try {
        await BackgroundCallService().clearNotifications();
      } catch (_) {}
    }
  });
}

Future<void> _showIncomingCallNotification(Map<String, dynamic> data) async {
  try {
    await _initializeLocalNotifications();

    final callerName = (data['callerName'] ?? data['from'] ?? 'Unknown').toString();
    final isVideo = (data['isVideoCall']?.toString().toLowerCase() == 'true');
    final title = isVideo ? 'Incoming video call' : 'Incoming voice call';
    final body = callerName;

    const androidDetails = AndroidNotificationDetails(
      _incomingCallChannelId,
      _incomingCallChannelName,
      channelDescription: 'Full-screen incoming call alerts',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      ticker: 'Incoming call',
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('ACCEPT_CALL', 'Accept', showsUserInterface: true),
        AndroidNotificationAction('DECLINE_CALL', 'Decline', cancelNotification: true),
      ],
    );

    const details = NotificationDetails(android: androidDetails);

    // Use a stable ID for “one active incoming call”.
    await _localNotifications.show(
      9991,
      title,
      body,
      details,
      payload: data.toString(),
    );
  } catch (e) {
    debugPrint('[LOCAL_NOTIF] failed to show incoming call notification: $e');
  }
}

/// Exposes the current device FCM token.
Future<String?> getFcmDeviceToken() {
  return FirebaseMessaging.instance.getToken();
}

/// Stub hook: send the FCM token to your backend.
///
/// Call this after login, and also on `FirebaseMessaging.instance.onTokenRefresh`.
Future<void> sendFcmTokenToBackend(String token) async {
  debugPrint('[FCM] send token to backend: $token');

  // We need the user's JWT to associate this device token to the authenticated user.
  // This uses the existing AuthService storage.
  try {
    final auth = AuthService();
    final jwt = await auth.getToken();
    if (jwt == null || jwt.isEmpty) {
      debugPrint('[FCM] no auth token yet; skipping backend token registration');
      return;
    }

    await auth.registerFcmToken(
      baseUrl: _AppNavigatorState._primaryBaseUrl,
      authToken: jwt,
      fcmToken: token,
    );
    debugPrint('[FCM] token registered with backend');
  } catch (e) {
    debugPrint('[FCM] failed to register token with backend: $e');
  }
}

Future<void> _initializeFcm() async {
  // Request notification permission (Android 13+).
  // Even for data-only pushes, you typically want permission so you can show
  // a local full-screen/heads-up incoming call notification.
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  debugPrint('[FCM] permission status=${settings.authorizationStatus}');

  // Get and register the token (send to backend).
  final token = await FirebaseMessaging.instance.getToken();
  debugPrint('[FCM] token=$token');
  if (token != null && token.isNotEmpty) {
    await sendFcmTokenToBackend(token);
  }

  // Token refresh must be handled to keep backend mapping valid.
  FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
    debugPrint('[FCM] token refreshed=$t');
    if (t.isNotEmpty) {
      await sendFcmTokenToBackend(t);
    }
  });

  // Foreground: app visible.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('[FCM][foreground] messageId=${message.messageId} data=${message.data}');
    final type = message.data['type']?.toString();
    if (type == 'INCOMING_CALL') {
      showIncomingCallUI(message.data);
    }
  });

  // Background (app in background) and user taps notification.
  // NOTE: For data-only pushes there may be no notification to tap, but we
  // still keep this for completeness if you show a local notification.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('[FCM][opened] messageId=${message.messageId} data=${message.data}');
    final type = message.data['type']?.toString();
    if (type == 'INCOMING_CALL') {
      showIncomingCallUI(message.data);
    } else if (message.data['incomingCall'] == 'true') {
      // Handle notification tap from our enhanced notification
      _handleNotificationTap(message.data);
    }
  });

  // Killed-state: app launched from a terminated state due to a message.
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('[FCM][initial] messageId=${initialMessage.messageId} data=${initialMessage.data}');
    final type = initialMessage.data['type']?.toString();
    if (type == 'INCOMING_CALL') {
      showIncomingCallUI(initialMessage.data);
    } else if (initialMessage.data['incomingCall'] == 'true') {
      // Handle notification tap from our enhanced notification
      _handleNotificationTap(initialMessage.data);
    }
  }
}

void _handleNotificationTap(Map<String, dynamic> data) {
  debugPrint('[FCM][notification_tap] Opening call screen with data: $data');
  
  final callId = data['callId']?.toString() ?? '';
  final from = data['callerId']?.toString() ?? data['from']?.toString() ?? '';
  final roomId = data['roomId']?.toString() ?? '';
  final isVideo = data['isVideo']?.toString() == 'true';
  final autoAnswer = data['autoAnswer']?.toString() == 'true';
  final showCallScreen = data['showCallScreen']?.toString() == 'true';
  
  if (callId.isNotEmpty && from.isNotEmpty) {
    if (showCallScreen) {
      // Navigate directly to the main CallScreen (full call interface)
      // If autoAnswer is true, set up pending auto-accept for when the offer arrives
      if (autoAnswer) {
        debugPrint('[FCM][notification_tap] Setting up auto-accept for call from $from');
        final callService = CallService();
        // Set pending auto-accept - this will be triggered when the incoming call event arrives
        callService.armAutoAccept({
          'from': from,
          'roomId': roomId,
          'callId': callId,
        });
      }
      
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => CallScreen(
            userId: '', // Will be set by CallService
            primaryBaseUrl: 'https://rjsw7olwsc3y.share.zrok.io',
            fallbackBaseUrl: 'http://localhost:5000',
          ),
        ),
      );
    } else {
      // Navigate to incoming call screen (for manual answer)
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => IncomingCallScreen(
            callId: callId,
            remoteUserId: from,
            roomId: roomId,
            isVideoCall: isVideo,
            autoAnswer: autoAnswer,
          ),
        ),
      );
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android-only: initialize Firebase/FCM.
  // Web was blank because firebase_core_web requires web Firebase config.
  // Since your requirement is Android only, we skip Firebase init on web.
  if (!kIsWeb) {
    // Firebase must be initialized before using Firebase Messaging.
    await Firebase.initializeApp();

    // Register background handler before `runApp`.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await Hive.initFlutter();
  await Hive.openBox<dynamic>('auth');

  if (!kIsWeb) {
    try {
      final pending = await PendingCallAccept.consume();
      if (pending != null) {
        CallService().armAutoAccept(pending);
      }
    } catch (_) {}
  }

  if (!kIsWeb) {
    await BackgroundCallService().initialize();
  }

  // Initialize local notifications early so full-screen intents are ready.
  if (!kIsWeb) {
    await _initializeLocalNotifications();
  }

  // Initialize FCM after Firebase initialization.
  if (!kIsWeb) {
    await _initializeFcm();
  }

  // Must be set up after plugins are registered.
  if (!kIsWeb) {
    _setupCallkitEventHandlers();
  }
  
  runApp(const CallingSystemApp());
}

/// Main application widget for the Calling System
class CallingSystemApp extends StatelessWidget {
  const CallingSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calling System',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AppNavigator(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Navigation widget that manages the app flow
class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> with WidgetsBindingObserver {
  String? _registeredUserId;
  String? _callUserId;
  bool _isInitializing = false;
  bool _isBootstrappingAuth = true;

  static const String _primaryBaseUrl = 'https://rjsw7olwsc3y.share.zrok.io';
  static const String _fallbackBaseUrl = 'http://localhost:5000';
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapAuth();
    _initializeBackgroundServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Clean up CallService when app is disposed
    CallService().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
        debugPrint('🔧 App paused - KEEPING socket connected for background calls');
        // DON'T disconnect socket - keep it alive for background calls
        break;
      case AppLifecycleState.resumed:
        debugPrint('🔧 App resumed');
        // Socket should still be connected, no action needed
        break;
      case AppLifecycleState.detached:
        debugPrint('🔧 App detached - cleaning up resources');
        // Only cleanup when app is completely destroyed (rare)
        break;
      case AppLifecycleState.inactive:
        debugPrint('🔧 App inactive');
        break;
      case AppLifecycleState.hidden:
        debugPrint('🔧 App hidden - STILL KEEPING socket connected');
        // IMPORTANT: Keep socket connected even when hidden
        break;
    }
  }

  void _forceSocketDisconnect() {
    try {
      debugPrint('🔧 Force disconnecting socket...');
      final callService = CallService();
      if (!callService.isDisposed) {
        callService.dispose();
        SocketHeartbeat().stop();
        debugPrint('🔧 Socket force disconnected');
      } else {
        debugPrint('🔧 CallService already disposed');
      }
    } catch (e) {
      debugPrint('🔧 Error force disconnecting socket: $e');
    }
  }

  Future<void> _initializeBackgroundServices() async {
    try {
      // Initialize background services for persistent execution
      await BackgroundService().initialize();
      debugPrint('🟢 Background services initialized');
      
      // Start app state monitor service
      await BackgroundKeepAlivePlatform.startBackgroundService();
      debugPrint('🟢 App state monitor started');
      
      // Test background service after a delay
      Future.delayed(const Duration(seconds: 5), () {
        debugPrint('🔧 Background service should be running now');
      });
    } catch (e) {
      debugPrint('🔴 Failed to initialize background services: $e');
    }
  }

  Future<void> _bootstrapAuth() async {
    try {
      debugPrint('Bootstrapping auth...');
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('No token found, showing login screen');
        return;
      }
      debugPrint('Token found, validating with server...');

      try {
        debugPrint('Trying primary URL: $_primaryBaseUrl');
        final me = await _authService.me(baseUrl: _primaryBaseUrl, token: token);
        debugPrint('Successfully authenticated with primary URL');
        await _handleLoggedIn(me);
      } catch (e) {
        debugPrint('Primary URL failed: $e');
        debugPrint('Trying fallback URL: $_fallbackBaseUrl');
        final me = await _authService.me(baseUrl: _fallbackBaseUrl, token: token);
        debugPrint('Successfully authenticated with fallback URL');
        await _handleLoggedIn(me);
      }
    } catch (e) {
      debugPrint('All authentication attempts failed: $e');
      final cachedMe = await _authService.getCachedMe();
      if (cachedMe != null) {
        debugPrint('Using cached user data');
        await _handleLoggedIn(cachedMe);
        return;
      }

      final msg = e.toString();
      debugPrint('Auth error: $msg');
      if (msg.contains('Session expired') || msg.contains('status 401')) {
        debugPrint('Session expired, clearing token');
        await _authService.clearToken();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBootstrappingAuth = false;
        });
      }
    }
  }

  Future<String?> _ensureCallUserId(Map<String, dynamic> me) async {
    final existing = me['call_user_id'];
    if (existing is String && existing.trim().isNotEmpty) {
      return existing.trim();
    }

    if (!mounted) return null;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SetCallIdScreen(baseUrl: _primaryBaseUrl),
      ),
    );

    final callId = result?.trim();
    if (callId == null || callId.isEmpty) return null;
    return callId;
  }

  Future<void> _handleLoggedIn(Map<String, dynamic> me) async {
    final userId = me['user_id'];
    if (userId is! int) {
      throw Exception('Invalid user_id from server');
    }

    // Now that we have a valid auth session, register the device's FCM token
    // with the backend (FCM init may have happened before login).
    if (!kIsWeb) {
      try {
        final t = await getFcmDeviceToken();
        if (t != null && t.isNotEmpty) {
          await sendFcmTokenToBackend(t);
        }
      } catch (e) {
        debugPrint('[FCM] post-login token registration failed: $e');
      }
    }

    final callId = await _ensureCallUserId(me);
    if (callId == null || callId.isEmpty) {
      throw Exception('Missing call_user_id');
    }

    await _handleUserRegistration(callId, internalUserId: userId.toString());
  }

  /// Handle user registration and initialize CallService
  Future<void> _handleUserRegistration(
    String callUserId, {
    required String internalUserId,
  }) async {
    setState(() {
      _isInitializing = true;
    });

    try {
      // Initialize CallService with the user ID
      final callService = CallService();
      String connectedServerUrl = _primaryBaseUrl;
      try {
        await callService.initialize(callUserId, serverUrl: _primaryBaseUrl);
      } catch (_) {
        connectedServerUrl = _fallbackBaseUrl;
        await callService.initialize(callUserId, serverUrl: _fallbackBaseUrl);
      }

      if (!kIsWeb) {
        BackgroundCallService().connectToServer(
          callUserId,
          serverUrl: connectedServerUrl,
        );
      }
      
      if (mounted) {
        setState(() {
          _registeredUserId = internalUserId;
          _callUserId = callUserId;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        
        String errorMessage = 'Failed to connect';
        
        // Handle specific errors
        if (e.toString().contains('NotAllowedError') || 
            e.toString().contains('getUserMedia')) {
          errorMessage = 'Microphone permission denied. Please allow microphone access in app settings.';
        } else if (e.toString().contains('connection') || 
                   e.toString().contains('WebSocket')) {
          errorMessage = 'Cannot connect to server. Please check your internet connection.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
      
      rethrow;
    }
  }

  /// Handle user logout
  void _handleLogout() {
    setState(() {
      _registeredUserId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrappingAuth) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show loading screen while initializing
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to server...'),
            ],
          ),
        ),
      );
    }

    // Show auth screen if user is not logged in
    if (_registeredUserId == null) {
      return AuthScreen(
        baseUrl: _primaryBaseUrl,
        onLoggedIn: _handleLoggedIn,
      );
    }

    // Show call screen if user is registered
    return CallScreen(
      userId: _callUserId ?? _registeredUserId!,
      primaryBaseUrl: _primaryBaseUrl,
      fallbackBaseUrl: _fallbackBaseUrl,
    );
  }
}
