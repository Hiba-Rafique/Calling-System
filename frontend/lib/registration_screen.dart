import 'package:flutter/material.dart';

/// Registration screen for users to enter their unique ID
class RegistrationScreen extends StatefulWidget {
  final Function(String) onUserRegistered;

  const RegistrationScreen({
    super.key,
    required this.onUserRegistered,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _userIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  /// Handle user registration
  void _registerUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _userIdController.text.trim();
      
      // Call the callback to initialize the CallService
      await widget.onUserRegistered(userId);
      
      // Navigate will be handled by the parent widget
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calling System'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height - 
                       MediaQuery.of(context).padding.top - 
                       MediaQuery.of(context).padding.bottom - 
                       kToolbarHeight,
          ),
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // App icon and title
                  Icon(
                    Icons.phone_in_talk,
                    size: MediaQuery.of(context).size.width < 360 ? 60 : 80,
                    color: Theme.of(context).primaryColor,
                  ),
                  SizedBox(height: 16),
                  
                  Text(
                    'Welcome to Calling System',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: MediaQuery.of(context).size.width < 360 ? 20 : 24,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  
                  Text(
                    'Enter your unique user ID to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      fontSize: MediaQuery.of(context).size.width < 360 ? 14 : 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: MediaQuery.of(context).size.height < 600 ? 24 : 48),
                  
                  // Registration form
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // User ID input field
                        TextFormField(
                          controller: _userIdController,
                          decoration: const InputDecoration(
                            labelText: 'User ID',
                            hintText: 'Enter your unique user ID',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a user ID';
                            }
                            if (value.trim().length < 3) {
                              return 'User ID must be at least 3 characters';
                            }
                            // Allow alphanumeric characters and underscores
                            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value.trim())) {
                              return 'User ID can only contain letters, numbers, and underscores';
                            }
                            return null;
                          },
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _registerUser(),
                        ),
                        SizedBox(height: 24),
                        
                        // Register button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _registerUser,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Register & Continue',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: MediaQuery.of(context).size.height < 600 ? 16 : 32),
                  
                  // Instructions
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How it works:',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...const [
                            Text('• Enter a unique user ID to register'),
                            Text('• Call other users by entering their user ID'),
                            Text('• Accept or reject incoming calls'),
                            Text('• Enjoy real-time voice conversations'),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
