import 'package:flutter/material.dart';
import 'registration_screen.dart';
import 'call_screen.dart';
import 'call_service.dart';

void main() {
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
  bool _isInitializing = false;

  /// Handle user registration and initialize CallService
  Future<void> _handleUserRegistration(String userId) async {
    setState(() {
      _isInitializing = true;
    });

    try {
      // Initialize CallService with the user ID
      final callService = CallService();
      await callService.initialize(userId);
      
      setState(() {
        _registeredUserId = userId;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: ${e.toString()}'),
            backgroundColor: Colors.red,
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

    // Show registration screen if user is not registered
    if (_registeredUserId == null) {
      return RegistrationScreen(
        onUserRegistered: _handleUserRegistration,
      );
    }

    // Show call screen if user is registered
    return CallScreen(
      userId: _registeredUserId!,
    );
  }
}
