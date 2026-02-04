import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';
import 'sound_manager.dart';
import 'main.dart';

/// Screen for handling incoming calls when opened from notification
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String remoteUserId;
  final String roomId;
  final bool isVideoCall;
  final bool autoAnswer;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.remoteUserId,
    required this.roomId,
    required this.isVideoCall,
    this.autoAnswer = false,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final CallService _callService = CallService();
  bool _isConnecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    debugPrint('🔔 IncomingCallScreen initialized for call from ${widget.remoteUserId}');
    
    // Auto-answer if requested
    if (widget.autoAnswer) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _acceptCall();
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_isConnecting) return;
    
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      debugPrint('🔔 Accepting incoming call from ${widget.remoteUserId}');
      
      // Stop ringing sound
      SoundManager().stopRingingSound();
      
      // Accept the call using CallService
      await _callService.acceptCall(
        widget.remoteUserId,
        {}, // Offer data will be handled by CallService
        widget.callId,
      );
      
      // Just close this screen - the existing CallScreen will handle the call
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('🔔 Failed to accept call: $e');
      setState(() {
        _isConnecting = false;
        _error = 'Failed to accept call: $e';
      });
    }
  }

  Future<void> _declineCall() async {
    try {
      debugPrint('🔔 Declining incoming call from ${widget.remoteUserId}');
      
      // Stop ringing sound
      SoundManager().stopRingingSound();
      
      // End the call
      _callService.endCall();
      
      // Just close this screen
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('🔔 Failed to decline call: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _declineCall(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    widget.isVideoCall ? 'Video Call' : 'Voice Call',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // Balance the back button
                ],
              ),
            ),
            
            const Spacer(),
            
            // Caller info
            Column(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.remoteUserId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Incoming ${widget.isVideoCall ? 'video' : 'voice'} call',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
            
            const Spacer(),
            
            // Action buttons
            if (!_isConnecting) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  GestureDetector(
                    onTap: _declineCall,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 35,
                      ),
                    ),
                  ),
                  
                  // Accept button
                  GestureDetector(
                    onTap: _acceptCall,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.call,
                        color: Colors.white,
                        size: 35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ] else ...[
              // Connecting indicator
              const Column(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Connecting...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
