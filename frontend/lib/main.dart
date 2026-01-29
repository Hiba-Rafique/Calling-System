import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'auth_screen.dart';
import 'auth_service.dart';
import 'call_screen.dart';
import 'call_service.dart';
import 'background_call_service.dart';
import 'set_call_id_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await BackgroundCallService().initialize();
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

class _AppNavigatorState extends State<AppNavigator> {
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
    _bootstrapAuth();
  }

  Future<void> _bootstrapAuth() async {
    try {
      final token = await _authService.getToken();
      if (token == null || token.isEmpty) {
        return;
      }

      final me = await _authService.me(baseUrl: _primaryBaseUrl, token: token);
      await _handleLoggedIn(me);
    } catch (_) {
      await _authService.clearToken();
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
    );
  }
}
