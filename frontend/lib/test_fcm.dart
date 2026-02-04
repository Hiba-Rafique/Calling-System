import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class TestFCM extends StatelessWidget {
  const TestFCM({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test FCM')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                try {
                  final fcm = FirebaseMessaging.instance;
                  final token = await fcm.getToken();
                  print('FCM Token: $token');
                  
                  // Show token in dialog
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('FCM Token'),
                        content: SingleChildScrollView(
                          child: SelectableText(token ?? 'No token'),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  }
                } catch (e) {
                  print('Error getting FCM token: $e');
                }
              },
              child: const Text('Get FCM Token'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Subscribe to topic for testing
                  await FirebaseMessaging.instance.subscribeToTopic('test_calls');
                  print('Subscribed to test_calls topic');
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Subscribed to test_calls topic')),
                    );
                  }
                } catch (e) {
                  print('Error subscribing to topic: $e');
                }
              },
              child: const Text('Subscribe to Test Topic'),
            ),
          ],
        ),
      ),
    );
  }
}
