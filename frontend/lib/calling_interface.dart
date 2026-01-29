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
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
    _setupAnimations();
  }

  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
    _remoteRenderer.srcObject = _callService.remoteStream;
    _localRenderer.srcObject = _callService.localStream;

    _callService.remoteStreamStream.listen((stream) {
      _remoteRenderer.srcObject = stream;
      if (mounted) {
        setState(() {});
      }
    });

    _callService.localStreamStream.listen((stream) {
      _localRenderer.srcObject = stream;
      if (mounted) {
        setState(() {});
      }
    });

    _callService.callStateStream.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
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
    _remoteRenderer.dispose();
    _localRenderer.dispose();
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
            if (_callService.isVideoCall)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  mirror: false,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

            if (_callService.isVideoCall)
              Positioned(
                right: 16,
                top: 80,
                width: 120,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            // Background gradient
            if (!_callService.isVideoCall)
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
                      child: StreamBuilder<Duration>(
                        stream: _callService.callDurationStream,
                        initialData: _callService.callDuration,
                        builder: (context, snapshot) {
                          final duration = snapshot.data ?? Duration.zero;
                          return Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          );
                        },
                      ),
                    ),
                  
                  // Call controls
                  Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (_callService.callState == CallState.connected &&
                            _callService.isVideoCall)
                          _buildControlButton(
                            icon: _callService.isCameraOn
                                ? Icons.videocam
                                : Icons.videocam_off,
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _callService.toggleCamera();
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            backgroundColor: Colors.grey[800]!,
                          ),

                        // Speaker button (only when connected)
                        if (_callService.callState == CallState.connected)
                          _buildControlButton(
                            icon: _callService.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _callService.toggleSpeaker();
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            backgroundColor: Colors.grey[800]!,
                          ),
                        
                        // Mute button (only when connected)
                        if (_callService.callState == CallState.connected)
                          _buildControlButton(
                            icon: _callService.isMuted ? Icons.mic_off : Icons.mic,
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _callService.toggleMuted();
                              if (mounted) {
                                setState(() {});
                              }
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

                        if (_callService.callState == CallState.connected &&
                            _callService.isVideoCall)
                          _buildControlButton(
                            icon: Icons.cameraswitch,
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _callService.switchCamera();
                              if (mounted) {
                                setState(() {});
                              }
                            },
                            backgroundColor: Colors.grey[800]!,
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
