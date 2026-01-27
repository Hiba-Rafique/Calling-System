import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_service.dart';
import 'sound_manager.dart';

/// Full-screen calling interface with visual feedback
class CallingInterface extends StatefulWidget {
  final String targetUserId;
  final bool isIncoming;
  final Function() onCallEnd;

  const CallingInterface({
    super.key,
    required this.targetUserId,
    this.isIncoming = false,
    required this.onCallEnd,
  });

  @override
  State<CallingInterface> createState() => _CallingInterfaceState();
}

class _CallingInterfaceState extends State<CallingInterface>
    with TickerProviderStateMixin {
  final CallService _callService = CallService();
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    _pulseController.repeat(reverse: true);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String _getCallStatusText() {
    switch (_callService.callState) {
      case CallState.dialing:
        return 'Dialing...';
      case CallState.ringing:
        return 'Ringing...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      default:
        return 'Initializing...';
    }
  }

  Color _getStatusColor() {
    switch (_callService.callState) {
      case CallState.dialing:
        return Colors.orange;
      case CallState.ringing:
        return Colors.blue;
      case CallState.connecting:
        return Colors.purple;
      case CallState.connected:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_callService.callState) {
      case CallState.dialing:
        return Icons.phone_forwarded;
      case CallState.ringing:
        return Icons.phone_in_talk;
      case CallState.connecting:
        return Icons.settings_phone;
      case CallState.connected:
        return Icons.phone_in_talk;
      default:
        return Icons.phone;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.grey[900]!,
                    Colors.black,
                  ],
                ),
              ),
            ),
            
            // Main content
            SafeArea(
              child: Column(
                children: [
                  // Top status bar
                  Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Calling System',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.signal_cellular_4_bar,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.battery_full,
                              color: Colors.white,
                              size: 20,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  Spacer(),
                  
                  // User avatar and name
                  Column(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _callService.callState == CallState.ringing ||
                                   _callService.callState == CallState.dialing
                                ? _pulseAnimation.value
                                : 1.0,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[800],
                                border: Border.all(
                                  color: _getStatusColor(),
                                  width: 3,
                                ),
                              ),
                              child: Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                      SizedBox(height: 24),
                      
                      Text(
                        widget.targetUserId,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getStatusIcon(),
                            color: _getStatusColor(),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            _getCallStatusText(),
                            style: TextStyle(
                              color: _getStatusColor(),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  Spacer(),
                  
                  // Call duration (only show when connected)
                  if (_callService.callState == CallState.connected)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '00:00', // TODO: Implement call timer
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  
                  // Call controls
                  Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Speaker button (only when connected)
                        if (_callService.callState == CallState.connected)
                          _buildControlButton(
                            icon: Icons.volume_up,
                            onPressed: () {
                              // TODO: Toggle speaker
                              SoundManager().vibrateOnce();
                            },
                            backgroundColor: Colors.grey[800]!,
                          ),
                        
                        // Mute button (only when connected)
                        if (_callService.callState == CallState.connected)
                          _buildControlButton(
                            icon: Icons.mic,
                            onPressed: () {
                              // TODO: Toggle mute
                              SoundManager().vibrateOnce();
                            },
                            backgroundColor: Colors.grey[800]!,
                          ),
                        
                        // End call button
                        _buildControlButton(
                          icon: Icons.call_end,
                          onPressed: () async {
                            await SoundManager().vibrateOnce();
                            widget.onCallEnd();
                          },
                          backgroundColor: Colors.red,
                          iconSize: 32,
                        ),
                        
                        // Extra space for symmetry when not connected
                        if (_callService.callState != CallState.connected)
                          SizedBox(width: 64),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    double iconSize = 24,
  }) {
    return Container(
      width: 64,
      height: 64,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          shape: CircleBorder(),
          padding: EdgeInsets.all(16),
          elevation: 4,
        ),
        child: Icon(
          icon,
          size: iconSize,
        ),
      ),
    );
  }
}
