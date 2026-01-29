import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';
import 'calling_interface.dart';
import 'sound_manager.dart';

/// Main calling screen with UI for making and receiving calls
class CallScreen extends StatefulWidget {
  final String userId;

  const CallScreen({
    super.key,
    required this.userId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final TextEditingController _targetUserIdController = TextEditingController();
  
  bool _isInitialized = false;
  bool _showCallingInterface = false;
  String? _currentCallTarget;
  Map<String, dynamic>? _incomingCallOffer;
  String? _incomingCallId;
  MediaStream? _remoteStream;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  @override
  void dispose() {
    _targetUserIdController.dispose();
    super.dispose();
  }

  void _setupListeners() {
    _callService.callStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _showCallingInterface = state['callState'] != CallState.idle;
      });
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

  /// Show incoming call dialog
  void _showIncomingCallDialog() {
    showDialog(
      context: context,
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
                          onPressed: () {
                            Navigator.of(context).pop();
                            _rejectIncomingCall();
                          },
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
                          onPressed: () {
                            Navigator.of(context).pop();
                            _acceptIncomingCall();
                          },
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
    );
  }

  /// Accept incoming call
  Future<void> _acceptIncomingCall() async {
    if (_currentCallTarget == null || _incomingCallOffer == null || _incomingCallId == null) {
      return;
    }

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
        title: Text('Calling System - ${widget.userId}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(
              Icons.circle,
              color: Colors.green,
              size: 12,
            ),
          ),
        ],
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
            child: Column(
              children: [
                // Call status section
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _callService.isInCall ? Icons.phone_in_talk : Icons.phone,
                          color: _callService.isInCall ? Colors.green : Colors.grey,
                          size: MediaQuery.of(context).size.width < 360 ? 20 : 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _callService.isInCall ? 'In Call' : 'Ready to Call',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: MediaQuery.of(context).size.width < 360 ? 14 : 16,
                                ),
                              ),
                              if (_callService.isInCall && _callService.remoteUserId != null)
                                Text(
                                  'Connected to: ${_callService.remoteUserId}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_callService.isInCall)
                          ElevatedButton(
                            onPressed: _endCall,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            child: Text(
                              'End Call',
                              style: TextStyle(fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Remote audio indicator
                if (_remoteStream != null)
                  Card(
                    color: Colors.green[50],
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.volume_up, color: Colors.green, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Receiving audio from ${_callService.remoteUserId ?? 'remote user'}',
                              style: TextStyle(
                                color: Colors.green[800],
                                fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Local audio indicator
                if (_callService.localStream != null)
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.mic, color: Colors.blue, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Microphone is active',
                              style: TextStyle(
                                color: Colors.blue[800],
                                fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Spacer that adapts to screen size
                SizedBox(height: MediaQuery.of(context).size.height < 600 ? 20 : 40),
                
                // Call controls
                if (!_callService.isInCall) ...[
                  Text(
                    'Make a Call',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: MediaQuery.of(context).size.width < 360 ? 18 : 20,
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Responsive layout for call controls
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 500) {
                        // Horizontal layout for larger screens
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _targetUserIdController,
                                decoration: InputDecoration(
                                  labelText: 'User ID to Call',
                                  hintText: 'Enter user ID',
                                  prefixIcon: Icon(Icons.person),
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                textInputAction: TextInputAction.go,
                                onSubmitted: (_) => _makeCall(video: false),
                              ),
                            ),
                            SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () => _makeCall(video: false),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Icon(Icons.call),
                            ),
                            SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () => _makeCall(video: true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Icon(Icons.videocam),
                            ),
                          ],
                        );
                      } else {
                        // Vertical layout for smaller screens
                        return Column(
                          children: [
                            TextField(
                              controller: _targetUserIdController,
                              decoration: InputDecoration(
                                labelText: 'User ID to Call',
                                hintText: 'Enter user ID',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _makeCall(video: false),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _makeCall(video: false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.call),
                                    SizedBox(width: 8),
                                    Text('Voice Call'),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _makeCall(video: true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam),
                                    SizedBox(width: 8),
                                    Text('Video Call'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ],
                
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
