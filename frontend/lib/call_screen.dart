import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_service.dart';
import 'call_service.dart';
import 'calling_interface.dart';
import 'profile_screen.dart';
import 'call_log_screen.dart';
import 'set_call_id_screen.dart';
import 'main.dart';
import 'sound_manager.dart';

/// Main calling screen with UI for making and receiving calls
class CallScreen extends StatefulWidget {
  final String userId;
  final String primaryBaseUrl;
  final String fallbackBaseUrl;

  const CallScreen({
    super.key,
    required this.userId,
    required this.primaryBaseUrl,
    required this.fallbackBaseUrl,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final TextEditingController _targetUserIdController = TextEditingController();
  Box<dynamic>? _contactsBox;
  dynamic _contacts = const [];
  bool _isSyncingContacts = false;
  Timer? _searchDebounce;
  bool _isSearchingUsers = false;
  List<Map<String, dynamic>> _searchResults = const [];
  String? _searchError;
  String _myCallId = '';
  String? _lastShownError;
  
  bool _isInitialized = false;
  bool _showCallingInterface = false;
  String? _currentCallTarget;
  Map<String, dynamic>? _incomingCallOffer;
  String? _incomingCallId;
  MediaStream? _remoteStream;
  bool _isIncomingDialogVisible = false;
  Timer? _vibrationTimer;
  Timer? _notificationTimer;
  int _notificationId = 0;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _myCallId = widget.userId;
    _setupListeners();
    _initContacts();
    _initNotifications();
  }

  @override
  void didUpdateWidget(covariant CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_myCallId.isEmpty || _myCallId == oldWidget.userId) {
      _myCallId = widget.userId;
    }
  }

  Future<void> _openProfile() async {
    if (_callService.callState != CallState.idle) {
      _showErrorDialog('End the call before opening profile');
      return;
    }

    final newId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          primaryBaseUrl: widget.primaryBaseUrl,
          fallbackBaseUrl: widget.fallbackBaseUrl,
        ),
      ),
    );

    final trimmed = newId?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (mounted) {
      setState(() {
        _myCallId = trimmed;
      });
    }

    try {
      try {
        await _callService.initialize(trimmed, serverUrl: widget.primaryBaseUrl);
      } catch (_) {
        await _callService.initialize(trimmed, serverUrl: widget.fallbackBaseUrl);
      }
    } catch (_) {}
  }

  String get _effectiveMyCallId => _myCallId.isNotEmpty ? _myCallId : widget.userId;

  Future<void> _searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _isSearchingUsers = false;
          _searchError = null;
        });
      }
      return;
    }

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchError = 'Missing session';
        });
      }
      return;
    }

    setState(() {
      _isSearchingUsers = true;
      _searchError = null;
    });

    try {
      final res = await _withFallback(
        (url) => http.get(
          _uri(url, '/api/users/search').replace(queryParameters: {'q': q}),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final snippet = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
        debugPrint('User search failed status=${res.statusCode} body=$snippet');
        if (mounted) {
          setState(() {
            _searchResults = const [];
            _searchError = res.statusCode == 401
                ? 'Session expired'
                : 'Search failed (${res.statusCode})';
          });
        }
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return;

      final results = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final callId = (map['call_user_id'] ?? '').toString().trim();
          if (callId.isEmpty) continue;
          if (callId.toLowerCase() == _effectiveMyCallId.toLowerCase()) continue;
          results.add({
            'call_user_id': callId,
            'user_id': map['user_id'],
            'first_name': map['first_name'],
            'last_name': map['last_name'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _searchError = results.isEmpty ? 'No matches' : null;
        });
      }
    } catch (_) {
      debugPrint('User search request failed');
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchError = 'Search failed';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingUsers = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchUsers(value);
    });
  }

  bool _isAlreadyInContacts(String callId) {
    final existing = _contactsAsMaps();
    for (final c in existing) {
      final existingCallId = (c['call_user_id'] ?? c['display'] ?? '').toString().trim();
      if (existingCallId.isNotEmpty && existingCallId.toLowerCase() == callId.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _editCallId() async {
    if (_callService.callState != CallState.idle) {
      _showErrorDialog('End the call before changing your ID');
      return;
    }

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SetCallIdScreen(baseUrl: widget.primaryBaseUrl),
      ),
    );

    final newId = result?.trim();
    if (newId == null || newId.isEmpty) return;

    if (mounted) {
      setState(() {
        _myCallId = newId;
      });
    }

    try {
      try {
        await _callService.initialize(newId, serverUrl: widget.primaryBaseUrl);
      } catch (_) {
        await _callService.initialize(newId, serverUrl: widget.fallbackBaseUrl);
      }
    } catch (_) {
    }

    _targetUserIdController.clear();
    if (mounted) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _targetUserIdController.dispose();
    _vibrationTimer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initNotifications() async {
    if (!kIsWeb) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle notification tap
        },
      );
    }
  }

  Future<void> _initContacts() async {
    try {
      if (!Hive.isBoxOpen('contacts')) {
        _contactsBox = await Hive.openBox<dynamic>('contacts');
      } else {
        _contactsBox = Hive.box<dynamic>('contacts');
      }
      _loadContactsFromCache();
      await _syncContactsFromServer();
    } catch (_) {
    }
  }

  List<Map<String, dynamic>> _contactsAsMaps() {
    final val = _contacts;
    if (val is List<Map<String, dynamic>>) return val;

    if (val is List) {
      final converted = <Map<String, dynamic>>[];
      for (final item in val) {
        if (item is Map) {
          converted.add(Map<String, dynamic>.from(item));
        } else if (item is String) {
          final id = item.trim();
          if (id.isNotEmpty) {
            converted.add({
              'contact_id': null,
              'contact_user_id': null,
              'call_user_id': id,
              'display': id,
              'nickname': null,
            });
          }
        }
      }
      return converted;
    }

    return const <Map<String, dynamic>>[];
  }

  void _loadContactsFromCache() {
    final box = _contactsBox;
    if (box == null) return;
    final list = <Map<String, dynamic>>[];
    bool needsMigration = false;
    final legacyStrings = <String>[];

    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        list.add(map);
        continue;
      }

      if (val is String) {
        needsMigration = true;
        legacyStrings.add(val);
        continue;
      }

      if (val is List) {
        needsMigration = true;
        for (final item in val) {
          if (item is String) {
            legacyStrings.add(item);
          }
        }
        continue;
      }
    }

    if (needsMigration) {
      final unique = <String>{};
      for (final s in legacyStrings) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty) {
          unique.add(trimmed);
        }
      }

      final migrated = unique
          .map<Map<String, dynamic>>(
            (id) => {
              'contact_id': null,
              'contact_user_id': null,
              'call_user_id': id,
              'display': id,
              'nickname': null,
            },
          )
          .toList();

      list
        ..clear()
        ..addAll(migrated);

      try {
        box.clear();
        for (var i = 0; i < migrated.length; i++) {
          box.put('legacy_$i', migrated[i]);
        }
      } catch (_) {
      }
    }

    list.sort((a, b) {
      final an = (a['display'] ?? '').toString().toLowerCase();
      final bn = (b['display'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    if (mounted) {
      setState(() {
        _contacts = list;
      });
    }
  }

  Uri _uri(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: path);
  }

  Future<http.Response> _withFallback(
    Future<http.Response> Function(String baseUrl) request,
  ) async {
    try {
      return await request(widget.primaryBaseUrl).timeout(const Duration(seconds: 6));
    } catch (_) {
      return request(widget.fallbackBaseUrl).timeout(const Duration(seconds: 6));
    }
  }

  Future<String?> _getToken() async {
    try {
      final authBox = Hive.box<dynamic>('auth');
      final token = authBox.get('auth_token');
      return token is String ? token : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncContactsFromServer() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return;

    setState(() {
      _isSyncingContacts = true;
    });

    try {
      final res = await _withFallback(
        (url) => http.get(
          _uri(url, '/api/contacts'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return;

      final serverContacts = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final callId = (map['call_user_id'] ?? '').toString().trim();
          final display = callId.isNotEmpty
              ? callId
              : (map['contact_user_id'] ?? '').toString();
          serverContacts.add({
            'contact_id': map['contact_id'],
            'contact_user_id': map['contact_user_id'],
            'call_user_id': map['call_user_id'],
            'display': display,
            'nickname': map['nickname'],
          });
        }
      }

      final box = _contactsBox;
      if (box != null) {
        await box.clear();
        for (final c in serverContacts) {
          await box.put(c['contact_id'].toString(), c);
        }
      }

      _loadContactsFromCache();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingContacts = false;
        });
      }
    }
  }

  Future<void> _addContactFromInput() async {
    final callId = _targetUserIdController.text.trim();
    if (callId.isEmpty) return;
    if (callId == widget.userId) {
      _showErrorDialog('You cannot add yourself');
      return;
    }

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      _showErrorDialog('Missing session. Please login again.');
      return;
    }

    try {
      final res = await _withFallback(
        (url) => http.post(
          _uri(url, '/api/contacts'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'contact_call_id': callId,
          }),
        ),
      );

      if (res.statusCode == 409) {
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showErrorDialog('Failed to add contact');
        return;
      }

      await _syncContactsFromServer();
    } catch (_) {
      _showErrorDialog('Failed to add contact (offline)');
    }
  }

  Future<void> _removeContact(Map<String, dynamic> contact) async {
    final contactId = contact['contact_id'];
    if (contactId == null) return;
    final token = await _getToken();
    if (token == null || token.isEmpty) return;

    try {
      final res = await _withFallback(
        (url) => http.delete(
          _uri(url, '/api/contacts/$contactId'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }

      final box = _contactsBox;
      if (box != null) {
        await box.delete(contactId.toString());
      }
      _loadContactsFromCache();
    } catch (_) {
    }
  }

  void _setupListeners() {
    _callService.callStateStream.listen((state) {
      if (!mounted) return;
      final err = state['error']?.toString();
      if (err != null && err.isNotEmpty && err != _lastShownError) {
        _lastShownError = err;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        _showCallingInterface = state['callState'] != CallState.idle;
      });

      final cs = state['callState'];
      final error = state['error'] as String?;
      
      // Only dismiss dialog on specific cancellation errors
      if (cs == CallState.idle && _isIncomingDialogVisible && 
          error != null && error.isNotEmpty) {
        // Check for specific cancellation messages
        if (error.toLowerCase().contains('canceled') || 
            error.toLowerCase().contains('rejected') ||
            error.toLowerCase().contains('failed') ||
            error.toLowerCase().contains('busy') ||
            error.toLowerCase().contains('offline')) {
          _dismissIncomingCallDialog();
        }
      }
    });

    _callService.incomingCallStream.listen((callData) {
      if (!mounted) return;
      setState(() {
        _currentCallTarget = callData['from'];
        _incomingCallOffer = callData['offer'];
        _incomingCallId = callData['callId'];
      });

      _showIncomingCallDialog();
    });

    _callService.remoteStreamStream.listen((stream) {
      if (!mounted) return;
      setState(() {
        _remoteStream = stream;
      });
    });

    setState(() {
      _isInitialized = true;
    });
  }

  /// Start vibration and notification for incoming call
  void _startIncomingCallAlerts() {
    if (!kIsWeb && _currentCallTarget != null) {
      // Start vibration pattern
      _vibrationTimer?.cancel();
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (await Vibration.hasVibrator() ?? false) {
          await Vibration.vibrate(pattern: [0, 500, 500, 500]);
        }
      });

      // Show persistent notification
      _showIncomingCallNotification();
    }
  }

  /// Stop vibration and notifications
  void _stopIncomingCallAlerts() {
    _vibrationTimer?.cancel();
    _notificationTimer?.cancel();
    _notificationsPlugin.cancel(_notificationId);
  }

  /// Show incoming call notification
  Future<void> _showIncomingCallNotification() async {
    if (!kIsWeb && _currentCallTarget != null) {
      const androidDetails = AndroidNotificationDetails(
        'incoming_calls',
        'Incoming Calls',
        channelDescription: 'Notifications for incoming calls',
        importance: Importance.max,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
      );
      
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'incoming_call',
      );
      
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        _notificationId,
        'Incoming Call',
        'Call from $_currentCallTarget',
        details,
      );
    }
  }

  /// Dismiss incoming call dialog using multiple fallback methods
  void _dismissIncomingCallDialog({bool keepCallTarget = false}) {
    if (!_isIncomingDialogVisible) return;
    
    // Stop vibration and notifications first
    _stopIncomingCallAlerts();
    
    // Use WidgetsBinding to ensure this runs after the current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Method 1: Use global navigator key
        if (navigatorKey.currentContext != null) {
          Navigator.of(navigatorKey.currentContext!).pop();
        }
      } catch (_) {
        try {
          // Method 2: Use root navigator with context (if mounted)
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (_) {
          try {
            // Method 3: Use regular navigator (if mounted)
            if (mounted) {
              Navigator.of(context).pop();
            }
          } catch (_) {}
        }
      }
      
      _isIncomingDialogVisible = false;
      if (mounted) {
        setState(() {
          if (!keepCallTarget) {
            _currentCallTarget = null;
          }
          _incomingCallOffer = null;
          _incomingCallId = null;
        });
      }
    });
  }

  /// Show incoming call dialog
  void _showIncomingCallDialog() {
    _isIncomingDialogVisible = true;
    
    // Start vibration and notifications for mobile
    _startIncomingCallAlerts();
    
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button
          child: AlertDialog(
            backgroundColor: Colors.grey[900],
            contentPadding: EdgeInsets.zero,
            content: Container(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: Duration(seconds: 1),
                    child: Icon(
                      Icons.phone_in_talk,
                      size: 64,
                      color: Colors.green,
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Incoming Call',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    _currentCallTarget ?? 'Unknown',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Reject button
                      Container(
                        width: 60,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _rejectIncomingCall,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: CircleBorder(),
                            padding: EdgeInsets.all(16),
                          ),
                          child: Icon(Icons.call_end),
                        ),
                      ),
                      
                      // Accept button
                      Container(
                        width: 60,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _acceptIncomingCall,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: CircleBorder(),
                            padding: EdgeInsets.all(16),
                          ),
                          child: Icon(Icons.phone),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      _isIncomingDialogVisible = false;
      // Stop alerts when dialog is closed
      _stopIncomingCallAlerts();
    });
  }

  Future<void> _openCallLog() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallLogScreen(
          primaryBaseUrl: widget.primaryBaseUrl,
          fallbackBaseUrl: widget.fallbackBaseUrl,
        ),
      ),
    );
  }

  /// Accept incoming call
  Future<void> _acceptIncomingCall() async {
    if (_currentCallTarget == null || _incomingCallOffer == null || _incomingCallId == null) {
      return;
    }

    // Dismiss the dialog immediately but keep the call target
    _dismissIncomingCallDialog(keepCallTarget: true);

    try {
      await _callService.acceptCall(
        _currentCallTarget!,
        _incomingCallOffer!,
        _incomingCallId!,
      );
      
      setState(() {
        _incomingCallOffer = null;
        _incomingCallId = null;
      });
    } catch (e) {
      _showErrorDialog('Failed to accept call: ${e.toString()}');
    }
  }

  /// Reject incoming call
  void _rejectIncomingCall() {
    if (_currentCallTarget == null || _incomingCallId == null) {
      return;
    }

    // Dismiss the dialog immediately
    _dismissIncomingCallDialog();
    
    _callService.rejectCall(_currentCallTarget!, _incomingCallId!);
    
    setState(() {
      _currentCallTarget = null;
      _incomingCallOffer = null;
      _incomingCallId = null;
    });
  }

  /// Initiate a call to another user
  Future<void> _makeCall({required bool video}) async {
    final targetUserId = _targetUserIdController.text.trim();
    
    if (targetUserId.isEmpty) {
      _showErrorDialog('Please enter a user ID to call');
      return;
    }

    if (targetUserId == widget.userId) {
      _showErrorDialog('You cannot call yourself');
      return;
    }

    try {
      setState(() {
        _currentCallTarget = targetUserId;
      });

      await _callService.callUser(targetUserId, video: video);
      _targetUserIdController.clear();
    } catch (e) {
      setState(() {
        _currentCallTarget = null;
      });
      _showErrorDialog('Failed to make call: ${e.toString()}');
    }
  }

  /// End the current call
  void _endCall() {
    setState(() {
      _currentCallTarget = null;
    });
    _callService.endCall();
  }

  /// Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contactsAsMaps();

    // Show calling interface when in active call
    if (_showCallingInterface && _currentCallTarget != null) {
      return CallingInterface(
        targetUserId: _currentCallTarget!,
        isIncoming: _incomingCallOffer != null,
        onCallEnd: _endCall,
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Calling System'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing call service...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Calling System - $_effectiveMyCallId'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Call Log',
            onPressed: _openCallLog,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: _openProfile,
            icon: const Icon(Icons.account_circle),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSyncingContacts)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.white10,
              color: Theme.of(context).colorScheme.primary,
            ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _targetUserIdController,
                      decoration: InputDecoration(
                        labelText: 'Enter user id to call',
                        hintText: 'Enter user id to call',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      textInputAction: TextInputAction.go,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _makeCall(video: false),
                    ),

                    if (_isSearchingUsers)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),

                    if (_searchError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _searchError!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                    if (_searchResults.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: _searchResults.map((u) {
                            final callId = (u['call_user_id'] ?? '').toString();
                            final name = '${(u['first_name'] ?? '').toString()} ${(u['last_name'] ?? '').toString()}'.trim();
                            final isContact = _isAlreadyInContacts(callId);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text(callId, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: name.isEmpty ? null : Text(name),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isContact)
                                      IconButton(
                                        tooltip: 'Add contact',
                                        onPressed: () async {
                                          _targetUserIdController.text = callId;
                                          await SoundManager().vibrateOnce();
                                          await _addContactFromInput();
                                        },
                                        icon: const Icon(Icons.person_add_alt_1),
                                      ),
                                    IconButton(
                                      tooltip: 'Voice call',
                                      onPressed: () async {
                                        _targetUserIdController.text = callId;
                                        await SoundManager().vibrateOnce();
                                        await _makeCall(video: false);
                                      },
                                      icon: const Icon(Icons.call, color: Colors.green),
                                    ),
                                    IconButton(
                                      tooltip: 'Video call',
                                      onPressed: () async {
                                        _targetUserIdController.text = callId;
                                        await SoundManager().vibrateOnce();
                                        await _makeCall(video: true);
                                      },
                                      icon: const Icon(Icons.videocam, color: Colors.blue),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  _targetUserIdController.text = callId;
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                  ],
                ),
              ),
            ),
          ),

          if (contacts.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No contacts yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                itemCount: contacts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final c = contacts[index];
                  final id = (c['display'] ?? '').toString();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          id.isNotEmpty ? id.substring(0, 1).toUpperCase() : '?',
                        ),
                      ),
                      title: Text(
                        id,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Tap an icon to call',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Voice call',
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              _targetUserIdController.text = id;
                              await _makeCall(video: false);
                            },
                            icon: const Icon(Icons.call, color: Colors.green),
                          ),
                          IconButton(
                            tooltip: 'Video call',
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              _targetUserIdController.text = id;
                              await _makeCall(video: true);
                            },
                            icon: const Icon(Icons.videocam, color: Colors.blue),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _removeContact(c);
                            },
                            icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      onTap: () {
                        _targetUserIdController.text = id;
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
