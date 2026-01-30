import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'sound_manager.dart';
import 'web_unload.dart';

const String kSignalingServerUrl = 'https://rjsw7olwsc3y.share.zrok.io';

/// CallService manages WebRTC connections and Socket.IO signaling for voice calls
class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  // Socket.IO connection
  IO.Socket? _socket;
  
  // WebRTC components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _screenStream;
  bool _isVideoCall = false;
  bool _isCameraOn = false;
  bool _isScreenSharing = false;
  
  // User information
  String? _currentUserId;
  String? _remoteUserId;
  String? _callId;
  Timer? _dialingTimer;
  Timer? _ringingTimer;
  Timer? _connectingTimer;
  
  // Call state
  CallState _callState = CallState.idle;
  final StreamController<Map<String, dynamic>> _callStateController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _incomingCallController = StreamController.broadcast();

  DateTime? _callConnectedAt;
  Duration _callDuration = Duration.zero;
  Timer? _callDurationTimer;
  final StreamController<Duration> _callDurationController = StreamController.broadcast();

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  
  // ICE candidate buffering
  final List<Map<String, dynamic>> _bufferedIceCandidates = [];
  
  // Stream controllers for UI updates
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  
  // Getters for streams
  Stream<Map<String, dynamic>> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;
  Stream<Duration> get callDurationStream => _callDurationController.stream;
  
  // Getters for current state
  CallState get callState => _callState;
  bool get isInCall => _callState == CallState.connected;
  bool get isDialing => _callState == CallState.dialing;
  bool get isRinging => _callState == CallState.ringing;
  bool get isConnecting => _callState == CallState.connecting;
  String? get currentUserId => _currentUserId;
  String? get remoteUserId => _remoteUserId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  Duration get callDuration => _callDuration;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoCall => _isVideoCall;
  bool get isCameraOn => _isCameraOn;
  bool get isScreenSharing => _isScreenSharing;

  void _cancelCallTimers() {
    _dialingTimer?.cancel();
    _dialingTimer = null;
    _ringingTimer?.cancel();
    _ringingTimer = null;
    _connectingTimer?.cancel();
    _connectingTimer = null;
  }

  void _failCall(String reason, {bool notifyRemote = true}) {
    if (_callState == CallState.idle) return;

    final to = _remoteUserId;
    final from = _currentUserId;
    if (notifyRemote && to != null && from != null && _socket != null) {
      try {
        _socket!.emit('callFailed', {
          'to': to,
          'from': from,
          'reason': reason,
        });
      } catch (_) {}
    }

    SoundManager().playCallEndedSound();
    _endCall();
  }

  Future<void> _cleanupCallResources() async {
    try {
      _screenStream?.getTracks().forEach((t) => t.stop());
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;
    _isScreenSharing = false;

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _localStreamController.add(null);

    try {
      _remoteStream?.getTracks().forEach((t) => t.stop());
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    _remoteStreamController.add(null);

    try {
      await _peerConnection?.close();
      await _peerConnection?.dispose();
    } catch (_) {}
    _peerConnection = null;
  }

  Future<void> startScreenShare() async {
    if (_peerConnection == null) {
      throw Exception('WebRTC not initialized');
    }
    if (_callState != CallState.connected) {
      throw Exception('Screen sharing is only available during an active call');
    }
    if (!_isVideoCall) {
      throw Exception('Start a video call to share your screen');
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      throw Exception(
        'iOS screen sharing requires a ReplayKit Broadcast Extension (native iOS setup) and is not enabled yet',
      );
    }

    const mediaProjectionChannel = MethodChannel('com.example.frontend/media_projection');

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await mediaProjectionChannel.invokeMethod('start');
        } catch (_) {
        }
      }

      final display = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': false,
      });

      final tracks = display.getVideoTracks();
      if (tracks.isEmpty) {
        throw Exception('No screen video track available');
      }

      _screenStream?.getTracks().forEach((t) => t.stop());
      await _screenStream?.dispose();
      _screenStream = display;

      final screenTrack = tracks.first;
      _isScreenSharing = true;
      _isCameraOn = true;

      try {
        screenTrack.onEnded = () {
          stopScreenShare();
        };
      } catch (_) {
        // Some platforms may not support onEnded
      }

      final senders = await _peerConnection!.getSenders();
      final videoSender = senders.where((s) => s.track?.kind == 'video').toList();
      if (videoSender.isNotEmpty) {
        await videoSender.first.replaceTrack(screenTrack);
      } else {
        await _peerConnection!.addTrack(screenTrack, _screenStream!);
      }

      _localStreamController.add(_screenStream);
      _updateCallState(_callState);
    } catch (e) {
      debugPrint('Failed to start screen share: $e');

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await mediaProjectionChannel.invokeMethod('stop');
        } catch (_) {
        }
      }

      rethrow;
    }
  }

  Future<void> stopScreenShare() async {
    if (!_isScreenSharing) return;
    _isScreenSharing = false;

    final cameraTrack = _localStream?.getVideoTracks().isNotEmpty == true
        ? _localStream!.getVideoTracks().first
        : null;

    if (_peerConnection != null && cameraTrack != null) {
      try {
        final senders = await _peerConnection!.getSenders();
        final videoSender = senders.where((s) => s.track?.kind == 'video').toList();
        if (videoSender.isNotEmpty) {
          await videoSender.first.replaceTrack(cameraTrack);
        }
      } catch (e) {
        debugPrint('Failed to stop screen share (replaceTrack): $e');
      }
    }

    _screenStream?.getTracks().forEach((t) => t.stop());
    await _screenStream?.dispose();
    _screenStream = null;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      const mediaProjectionChannel = MethodChannel('com.example.frontend/media_projection');
      try {
        await mediaProjectionChannel.invokeMethod('stop');
      } catch (_) {
      }
    }

    _localStreamController.add(_localStream);
    _updateCallState(_callState);
  }

  Future<void> setCameraOn(bool enabled) async {
    _isCameraOn = enabled;
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    if (videoTracks.isNotEmpty) {
      videoTracks.first.enabled = enabled;
    }
    _updateCallState(_callState);
  }

  Future<void> toggleCamera() async {
    await setCameraOn(!_isCameraOn);
  }

  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? [];
    if (videoTracks.isEmpty) return;
    try {
      await Helper.switchCamera(videoTracks.first);
    } catch (e) {
      debugPrint('Switch camera failed: $e');
    }
  }

  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
    final audioTracks = _localStream?.getAudioTracks() ?? [];
    if (audioTracks.isNotEmpty) {
      audioTracks.first.enabled = !muted;
      if (!kIsWeb) {
        try {
          await Helper.setMicrophoneMute(muted, audioTracks.first);
        } catch (e) {
          debugPrint('Microphone mute failed: $e');
        }
      }
    }
    _updateCallState(_callState);
  }

  Future<void> toggleMuted() async {
    await setMuted(!_isMuted);
  }

  Future<void> setSpeakerOn(bool enabled) async {
    final previous = _isSpeakerOn;
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(enabled);
        await Future.delayed(const Duration(milliseconds: 250));
        await Helper.setSpeakerphoneOn(enabled);
        _isSpeakerOn = enabled;
      } catch (e) {
        _isSpeakerOn = previous;
        debugPrint('Speaker toggle failed: $e');
      }
    } else {
      _isSpeakerOn = enabled;
    }
    _updateCallState(_callState);
  }

  Future<void> toggleSpeaker() async {
    await setSpeakerOn(!_isSpeakerOn);
  }

  /// Initialize the service with user ID and connect to signaling server
  Future<void> initialize(String userId, {String serverUrl = kSignalingServerUrl}) async {
    _currentUserId = userId;

    if (kIsWeb) {
      registerWebUnloadHandler(() {
        if (_callState != CallState.idle) {
          endCall();
        }
      });
    }
    
    // Connect to Socket.IO server
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    
    // Set up Socket.IO event listeners
    _setupSocketListeners();
    
    // Initialize WebRTC
    await _initializeWebRTC(enableVideo: false);
  }

  /// Set up Socket.IO event listeners for signaling
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    // Handle incoming calls
    _socket!.on('incomingCall', (data) {
      debugPrint('Incoming call from: ${data['from']}');
      _remoteUserId = data['from'];
      _callId = '${data['from']}_$_currentUserId';
      
      // Update state to ringing
      _updateCallState(CallState.ringing);
      
      // Play ringing sound and vibrate
      SoundManager().playRingingSound();
      SoundManager().vibrateForIncomingCall();
      
      _incomingCallController.add({
        'from': data['from'],
        'offer': data['signal'], // Backend uses 'signal', not 'offer'
        'callId': _callId,
      });

      _ringingTimer?.cancel();
      _ringingTimer = Timer(const Duration(seconds: 30), () {
        if (_callState == CallState.ringing) {
          _failCall('no_answer');
        }
      });
    });
    
    // Handle call answers
    _socket!.on('callAccepted', (data) async {
      debugPrint('Call answered by: ${_remoteUserId}');
      await _handleAnswer(data); // Backend sends signal directly
    });
    
    // Handle ICE candidates
    _socket!.on('iceCandidate', (data) async {
      debugPrint('Received ICE candidate');
      await _handleIceCandidate(data); // Backend sends candidate directly
    });
    
    // Handle call ended
    _socket!.on('callEnded', (data) {
      final from = data['from']?.toString();
      debugPrint('Call ended by: $from');
      if (_callState == CallState.idle) {
        debugPrint('Already idle; ignoring callEnded');
        return;
      }
      if (from != null && from != _remoteUserId) {
        debugPrint('callEnded from unexpected user ($from); ignoring');
        return;
      }
      _endCall();
    });
    
    // Handle call rejected
    _socket!.on('callRejected', (data) {
      debugPrint('Call rejected by: ${data['from']}');
      SoundManager().playCallEndedSound();
      _endCall();
    });

    _socket!.on('callFailed', (data) {
      final from = data is Map ? data['from']?.toString() : null;
      final reason = data is Map ? data['reason']?.toString() : null;
      debugPrint('Call failed from: $from reason=$reason');

      if (_callState == CallState.idle) return;
      if (from != null && from != _remoteUserId) {
        debugPrint('callFailed from unexpected user ($from); ignoring');
        return;
      }

      SoundManager().playCallEndedSound();
      _endCall();
    });
    
    // Handle connection events
    _socket!.on('connect', (_) {
      debugPrint('Connected to signaling server');
      _socket!.emit('register', _currentUserId); // Backend expects 'register', not 'registerUser'
    });
    
    _socket!.on('disconnect', (_) {
      debugPrint('Disconnected from signaling server');

      if (_callState == CallState.dialing ||
          _callState == CallState.ringing ||
          _callState == CallState.connecting) {
        _failCall('signaling_disconnect', notifyRemote: false);
      }
    });
  }

  /// Initialize WebRTC peer connection and local media stream
  Future<void> _initializeWebRTC({required bool enableVideo}) async {
    try {
      _remoteStream = null;
      _remoteStreamController.add(null);

      _screenStream?.getTracks().forEach((t) => t.stop());
      await _screenStream?.dispose();
      _screenStream = null;
      _isScreenSharing = false;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;

      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _localStream = null;
      _localStreamController.add(null);

      // Create peer connection with STUN servers
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ]
      });
      
      // Set up peer connection event handlers
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        debugPrint('ICE candidate generated');
        _sendIceCandidate(candidate);
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('ICE connection state: $state');
        if ((_callState == CallState.connecting || _callState == CallState.dialing) &&
            (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateCompleted)) {
          _updateCallState(CallState.connected);
          SoundManager().playCallConnectedSound();
        }

        if (_callState != CallState.idle &&
            (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateClosed)) {
          _failCall('ice_$state');
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('Peer connection state: $state');
        if ((_callState == CallState.connecting || _callState == CallState.dialing) &&
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _updateCallState(CallState.connected);
          SoundManager().playCallConnectedSound();
        }

        if (_callState != CallState.idle &&
            (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
                state == RTCPeerConnectionState.RTCPeerConnectionStateClosed)) {
          _failCall('pc_$state');
        }
      };
      
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        debugPrint('Remote track added');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteStreamController.add(_remoteStream);
          final remoteTrackInfo = _remoteStream!
              .getTracks()
              .map((t) => '${t.kind}(enabled=${t.enabled})')
              .toList();
          debugPrint('Remote tracks: $remoteTrackInfo');
          if (_callState == CallState.connecting) {
            _updateCallState(CallState.connected);
            SoundManager().playCallConnectedSound();
          }
        }
      };
      
      if (!kIsWeb) {
        final micStatus = await Permission.microphone.request();
        if (!micStatus.isGranted) {
          throw Exception('Microphone permission denied');
        }

        if (enableVideo) {
          final camStatus = await Permission.camera.request();
          if (!camStatus.isGranted) {
            throw Exception('Camera permission denied');
          }
        }
      }

      // Get local audio stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': enableVideo
            ? {
                'facingMode': 'user',
              }
            : false,
      });

      _isCameraOn = enableVideo;
      final videoTracks = _localStream?.getVideoTracks() ?? [];
      if (videoTracks.isNotEmpty) {
        videoTracks.first.enabled = _isCameraOn;
      }

      _localStreamController.add(_localStream);
      
      // Add local tracks to peer connection
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      final localTrackInfo = _localStream!
          .getTracks()
          .map((t) => '${t.kind}(enabled=${t.enabled})')
          .toList();
      debugPrint('Local tracks: $localTrackInfo');
      
      debugPrint('WebRTC initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize WebRTC: $e');
      rethrow;
    }
  }

  bool _offerContainsVideo(Map<String, dynamic> offerData) {
    final sdp = offerData['sdp'];
    if (sdp is String) {
      return sdp.contains('\nm=video') || sdp.contains('\rm=video');
    }
    return false;
  }

  /// Initiate a call to another user
  Future<void> callUser(String targetUserId, {bool video = false}) async {
    if (_callState != CallState.idle && _callState != CallState.ringing) {
      throw Exception('Already in a call');
    }

    try {
      _isVideoCall = video;
      await _initializeWebRTC(enableVideo: video);

      _remoteUserId = targetUserId;
      _callId = '${_currentUserId}_$targetUserId';
      
      // Update state to dialing
      _updateCallState(CallState.dialing);
      
      // Play dialing sound
      await SoundManager().playDialingSound();
      
      // Start dialing timer for timeout
      _dialingTimer?.cancel();
      _dialingTimer = Timer(const Duration(seconds: 30), () {
        if (_callState == CallState.dialing || _callState == CallState.connecting) {
          _failCall('timeout');
        }
      });

      _connectingTimer?.cancel();
      _connectingTimer = Timer(const Duration(seconds: 30), () {
        if (_callState == CallState.connecting) {
          _failCall('connect_timeout');
        }
      });
      
      // Create offer
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': video ? 1 : 0,
      });
      
      // Set local description
      await _peerConnection!.setLocalDescription(offer);
      
      // Send offer to target user via signaling server
      _socket!.emit('callUser', {
        'userToCall': targetUserId, // Backend expects 'userToCall'
        'signalData': offer.toMap(), // Backend expects 'signalData'
        'from': _currentUserId,
      });
      
      debugPrint('Call initiated to: $targetUserId');
    } catch (e) {
      _updateCallState(CallState.idle);

      await _cleanupCallResources();
      debugPrint('Failed to initiate call: $e');
      rethrow;
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(String from, Map<String, dynamic> offerData, String callId) async {
    if (_callState != CallState.idle && _callState != CallState.ringing) {
      throw Exception('Already in a call');
    }
    
    try {
      final hasVideo = _offerContainsVideo(offerData);
      _isVideoCall = hasVideo;
      await _initializeWebRTC(enableVideo: hasVideo);

      if (_peerConnection == null) {
        throw Exception('WebRTC not initialized');
      }

      _remoteUserId = from;
      _callId = callId;
      
      // Update state to connecting
      _updateCallState(CallState.connecting);

      _connectingTimer?.cancel();
      _connectingTimer = Timer(const Duration(seconds: 30), () {
        if (_callState == CallState.connecting) {
          _failCall('connect_timeout');
        }
      });
      
      // Stop ringing sound
      SoundManager().stopRingingSound();
      
      // Vibrate for call acceptance
      await SoundManager().vibrateOnce();
      
      debugPrint('Setting remote description from offer: $offerData');
      
      // IMPORTANT: Set remote description FIRST before creating answer
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type'])
      );
      
      // Process any buffered ICE candidates
      await _processBufferedIceCandidates();
      
      // Now create answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': hasVideo ? 1 : 0,
      });
      
      // Set local description
      await _peerConnection!.setLocalDescription(answer);
      
      // Send answer to caller
      _socket!.emit('answerCall', {
        'to': from, // Backend expects 'to'
        'signal': answer.toMap(), // Backend expects 'signal'
      });

      if (!kIsWeb) {
        try {
          final audioTracks = _localStream?.getAudioTracks() ?? [];
          if (audioTracks.isNotEmpty) {
            await Helper.setMicrophoneMute(false, audioTracks.first);
          }
          await setSpeakerOn(true);
        } catch (e) {
          debugPrint('Audio route setup failed: $e');
        }
      }
      
      debugPrint('Call accepted from: $from');
    } catch (e) {
      _updateCallState(CallState.idle);
      _failCall('accept_failed', notifyRemote: true);
      debugPrint('Failed to accept call: $e');
      rethrow;
    }
  }

  /// Reject an incoming call
  void rejectCall(String from, String callId) {
    // Stop ringing sound
    SoundManager().stopRingingSound();
    
    // Reset state to idle
    _updateCallState(CallState.idle);
    _remoteUserId = null;
    _callId = null;
    _isVideoCall = false;
    _isCameraOn = false;
    _isScreenSharing = false;

    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;
    
    if (_socket != null && _currentUserId != null) {
      try {
        _socket!.emit('rejectCall', {
          'to': from,
          'from': _currentUserId,
          'reason': 'rejected',
        });
      } catch (_) {}
    }

    debugPrint('Call rejected from: $from');
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(Map<String, dynamic> signalData) async {
    try {
      // Cancel dialing timer
      _dialingTimer?.cancel();
      _dialingTimer = null;
      
      // Update state to connecting
      _updateCallState(CallState.connecting);
      
      debugPrint('Received answer data: $signalData');
      
      // Handle different possible data structures from backend
      String sdp;
      String type;
      
      if (signalData.containsKey('sdp') && signalData.containsKey('type')) {
        // Direct structure: {sdp: "...", type: "answer"}
        sdp = signalData['sdp'];
        type = signalData['type'];
      } else if (signalData.containsKey('signal')) {
        // Nested structure: {signal: {sdp: "...", type: "answer"}}
        final signal = signalData['signal'];
        sdp = signal['sdp'];
        type = signal['type'];
      } else {
        throw Exception('Invalid answer data structure: $signalData');
      }
      
      // Check current remote description before setting
      final currentRemoteDesc = await _peerConnection!.getRemoteDescription();
      if (currentRemoteDesc != null && currentRemoteDesc.type == 'answer') {
        debugPrint('Remote description already set as answer, skipping...');
        _updateCallState(CallState.connected);
        SoundManager().playCallConnectedSound();
        return;
      }
      
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type)
      );

      if (!kIsWeb) {
        try {
          final audioTracks = _localStream?.getAudioTracks() ?? [];
          if (audioTracks.isNotEmpty) {
            await Helper.setMicrophoneMute(false, audioTracks.first);
          }
          await setSpeakerOn(true);
        } catch (e) {
          debugPrint('Audio route setup failed: $e');
        }
      }
      
      debugPrint('Call answered successfully');
    } catch (e) {
      _failCall('answer_failed');
      debugPrint('Failed to handle answer: $e');
    }
  }

  /// Process buffered ICE candidates after remote description is set
  Future<void> _processBufferedIceCandidates() async {
    if (_bufferedIceCandidates.isEmpty) return;
    
    debugPrint('Processing ${_bufferedIceCandidates.length} buffered ICE candidates');
    
    for (final candidateData in _bufferedIceCandidates) {
      try {
        await _handleIceCandidate(candidateData);
      } catch (e) {
        debugPrint('Failed to process buffered ICE candidate: $e');
      }
    }
    
    _bufferedIceCandidates.clear();
  }

  /// Handle incoming ICE candidate
  Future<void> _handleIceCandidate(Map<String, dynamic> candidateData) async {
    try {
      debugPrint('Received ICE candidate data: $candidateData');
      
      // Check if remote description is set before adding ICE candidates
      final remoteDesc = await _peerConnection?.getRemoteDescription();
      if (remoteDesc == null) {
        debugPrint('Remote description not set yet, buffering ICE candidate');
        // Buffer the candidate for later
        _bufferedIceCandidates.add(candidateData);
        return;
      }
      
      // Handle different possible data structures from backend
      Map<String, dynamic> candidate;
      
      if (candidateData.containsKey('candidate') && candidateData.containsKey('sdpMid')) {
        // Direct structure: {candidate: "...", sdpMid: "...", sdpMLineIndex: ...}
        candidate = candidateData;
      } else if (candidateData.containsKey('candidate') && candidateData['candidate'] is Map) {
        // Nested structure: {candidate: {candidate: "...", sdpMid: "...", sdpMLineIndex: ...}}
        candidate = candidateData['candidate'];
      } else {
        throw Exception('Invalid ICE candidate data structure: $candidateData');
      }
      
      RTCIceCandidate iceCandidate = RTCIceCandidate(
        candidate['candidate'],
        candidate['sdpMid'],
        candidate['sdpMLineIndex'],
      );
      
      await _peerConnection!.addCandidate(iceCandidate);
      debugPrint('ICE candidate added successfully');
      
      // Check if connection is established after adding candidate
      if (_callState == CallState.connecting) {
        // Give it a moment to establish connection
        Future.delayed(Duration(seconds: 2), () {
          if (_callState == CallState.connecting && _remoteStream != null) {
            _updateCallState(CallState.connected);
            SoundManager().playCallConnectedSound();
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to handle ICE candidate: $e');
    }
  }

  /// Send ICE candidate to remote user
  void _sendIceCandidate(RTCIceCandidate candidate) {
    if (_remoteUserId == null) return;
    
    _socket!.emit('iceCandidate', {
      'to': _remoteUserId, // Backend expects 'to'
      'candidate': candidate.toMap(),
    });
  }

  /// End the current call
  void endCall() {
    if (_remoteUserId != null && _socket != null) {
      _socket!.emit('endCall', {
        'to': _remoteUserId,
        'from': _currentUserId,
      });
    }
    _endCall();
  }

  /// Internal method to clean up call state
  void _endCall() {
    // Cancel any timers
    _cancelCallTimers();
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    _callDuration = Duration.zero;
    _callConnectedAt = null;
    
    // Stop all sounds
    SoundManager().stopAll();
    
    // Play call ended sound if we were in a call
    if (_callState == CallState.connected || _callState == CallState.dialing) {
      SoundManager().playCallEndedSound();
    }

    // Tear down WebRTC to stop audio/video immediately
    _cleanupCallResources();
    
    _updateCallState(CallState.idle);
    _remoteUserId = null;
    _callId = null;
    _isVideoCall = false;
    _isCameraOn = false;
    _isSpeakerOn = false;
    _isMuted = false;
    
    debugPrint('Call ended');
  }
  
  /// Update call state and notify listeners
  void _updateCallState(CallState newState) {
    final previousState = _callState;
    _callState = newState;

    if (previousState != CallState.connected && newState == CallState.connected) {
      _cancelCallTimers();
      _callConnectedAt = DateTime.now();
      _callDuration = Duration.zero;
      _callDurationController.add(_callDuration);
      _callDurationTimer?.cancel();
      _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_callConnectedAt == null) return;
        _callDuration = DateTime.now().difference(_callConnectedAt!);
        _callDurationController.add(_callDuration);
      });
    }

    if (previousState == CallState.connected && newState != CallState.connected) {
      _callDurationTimer?.cancel();
      _callDurationTimer = null;
    }

    _callStateController.add({
      'callState': _callState,
      'remoteUserId': _remoteUserId,
      'isMuted': _isMuted,
      'isSpeakerOn': _isSpeakerOn,
      'isVideoCall': _isVideoCall,
      'isCameraOn': _isCameraOn,
      'isScreenSharing': _isScreenSharing,
      'callDurationMs': _callDuration.inMilliseconds,
    });
  }

  /// Dispose of all resources
  void dispose() {
    _endCall();
    
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();
    
    _peerConnection?.close();
    _peerConnection?.dispose();
    
    _socket?.disconnect();
    _socket?.dispose();
    
    _callStateController.close();
    _incomingCallController.close();
    _remoteStreamController.close();
    _localStreamController.close();
    _callDurationController.close();
    
    SoundManager().dispose();
    
    debugPrint('CallService disposed');
  }
}
