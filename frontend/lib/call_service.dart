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
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final Map<String, MediaStream> _remoteStreamsByUser = {};
  MediaStream? _screenStream;
  bool _isVideoCall = false;
  bool _isCameraOn = false;
  bool _isScreenSharing = false;
  
  // User information
  String? _currentUserId;
  String? _remoteUserId;
  String? _callId;
  String? _roomId;
  final Set<String> _participants = {};
  Timer? _dialingTimer;
  Timer? _ringingTimer;
  Timer? _connectingTimer;
  
  // Call state
  CallState _callState = CallState.idle;
  final StreamController<Map<String, dynamic>> _callStateController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _incomingCallController = StreamController.broadcast();
  String? _lastError;

  DateTime? _callConnectedAt;
  Duration _callDuration = Duration.zero;
  Timer? _callDurationTimer;
  final StreamController<Duration> _callDurationController = StreamController.broadcast();

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  
  // ICE candidate buffering
  final List<Map<String, dynamic>> _bufferedIceCandidates = [];
  final Map<String, List<Map<String, dynamic>>> _bufferedRoomIceCandidates = {};
  
  // Stream controllers for UI updates
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamsController =
      StreamController<Map<String, MediaStream>>.broadcast();
  final _roomInviteController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Getters for streams
  Stream<Map<String, dynamic>> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  Stream<Map<String, MediaStream>> get remoteStreamsStream =>
      _remoteStreamsController.stream;
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;
  Stream<Duration> get callDurationStream => _callDurationController.stream;
  Stream<Map<String, dynamic>> get roomInviteStream => _roomInviteController.stream;
  
  // Getters for current state
  CallState get callState => _callState;
  bool get isInCall => _callState == CallState.connected;
  bool get isDialing => _callState == CallState.dialing;
  bool get isRinging => _callState == CallState.ringing;
  bool get isConnecting => _callState == CallState.connecting;
  String? get currentUserId => _currentUserId;
  String? get remoteUserId => _remoteUserId;
  String? get roomId => _roomId;
  List<String> get participants => _participants.toList()..sort();
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  Map<String, MediaStream> get remoteStreams => Map.unmodifiable(_remoteStreamsByUser);
  Duration get callDuration => _callDuration;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoCall => _isVideoCall;
  String? get lastError => _lastError;
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

  bool _isRoomCall() {
    return _roomId != null && _roomId!.isNotEmpty;
  }

  bool _shouldInitiateOffer(String otherUserId) {
    final me = _currentUserId;
    if (me == null) return false;
    return me.compareTo(otherUserId) < 0;
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

    for (final pc in _peerConnections.values) {
      try {
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    _peerConnections.clear();

    for (final s in _remoteStreamsByUser.values) {
      try {
        s.getTracks().forEach((t) => t.stop());
        await s.dispose();
      } catch (_) {}
    }
    _remoteStreamsByUser.clear();
    _bufferedRoomIceCandidates.clear();
    _remoteStreamsController.add({});

    _roomId = null;
    _participants.clear();
  }

  Future<RTCPeerConnection> _createPeerConnectionFor(
    String peerId, {
    required bool enableVideo,
  }) async {
    if (_peerConnections.containsKey(peerId)) {
      return _peerConnections[peerId]!;
    }

    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ]
    });

    _peerConnections[peerId] = pc;

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final rid = _roomId;
      if (_socket == null || _currentUserId == null) return;
      if (rid != null && rid.isNotEmpty) {
        _socket!.emit('roomIceCandidate', {
          'roomId': rid,
          'to': peerId,
          'from': _currentUserId,
          'candidate': candidate.toMap(),
        });
      } else {
        _socket!.emit('iceCandidate', {
          'to': peerId,
          'from': _currentUserId,
          'candidate': candidate.toMap(),
        });
      }
    };

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      final stream = event.streams[0];
      _remoteStreamsByUser[peerId] = stream;
      _remoteStreamsController.add(Map<String, MediaStream>.from(_remoteStreamsByUser));

      // Backward compatibility: set primary remoteStream to first remote stream.
      _remoteStream ??= stream;
      _remoteStreamController.add(_remoteStream);

      if (_callState == CallState.connecting) {
        _updateCallState(CallState.connected);
        SoundManager().playCallConnectedSound();
      }
    };

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          await pc.addTrack(track, _localStream!);
        } catch (_) {}
      }
    } else {
      await _ensureLocalStream(enableVideo: enableVideo);
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          try {
            await pc.addTrack(track, _localStream!);
          } catch (_) {}
        }
      }
    }

    return pc;
  }

  Future<void> _ensureLocalStream({required bool enableVideo}) async {
    if (_localStream != null) {
      if (enableVideo && _localStream!.getVideoTracks().isEmpty) {
        // Re-init if we are upgrading from audio-only to video.
      } else {
        return;
      }
    }

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

    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();

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

    // Dispose existing socket if any
    if (_socket != null) {
      try {
        _socket!.disconnect();
        _socket!.dispose();
      } catch (_) {}
      _socket = null;
    }

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
      _roomId = data is Map ? data['roomId']?.toString() : null;
      _participants
        ..clear()
        ..addAll([
          if (_currentUserId != null) _currentUserId!,
          if (_remoteUserId != null) _remoteUserId!,
        ]);
      _callId = _roomId ?? '${data['from']}_$_currentUserId';
      
      // Update state to ringing
      _updateCallState(CallState.ringing);
      
      // Play ringing sound and vibrate
      SoundManager().playRingingSound();
      SoundManager().vibrateForIncomingCall();
      
      final rawOffer = (data is Map && data['signal'] is Map)
          ? Map<String, dynamic>.from(data['signal'] as Map)
          : <String, dynamic>{};
      if (_roomId != null && _roomId!.isNotEmpty) {
        rawOffer['roomId'] = _roomId;
      }

      _incomingCallController.add({
        'from': data['from'],
        'offer': rawOffer, // Backend uses 'signal', not 'offer'
        'callId': _callId,
        'roomId': _roomId,
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
      debugPrint('Call answered by: ${_remoteUserId}, data: $data');
      debugPrint('Current call state when answer received: $_callState');
      if (data is Map && data['signal'] != null) {
        _roomId = data['roomId']?.toString() ?? _roomId;
        final from = data['from']?.toString();
        if (from != null && from.isNotEmpty) {
          _remoteUserId = from;
          _participants
            ..clear()
            ..addAll([
              if (_currentUserId != null) _currentUserId!,
              from,
            ]);
        }
        debugPrint('Handling answer with signal: ${data['signal']}');
        await _handleAnswer(data['signal']);
        debugPrint('Answer handled successfully');
      } else {
        debugPrint('Handling legacy answer');
        await _handleAnswer(data); // Legacy (1:1)
        debugPrint('Legacy answer handled successfully');
      }
    });
    
    // Handle ICE candidates for 1:1 calls
    _socket!.on('iceCandidate', (data) async {
      debugPrint('Received ICE candidate: $data');
      if (data is Map && data['candidate'] != null && data['from'] != null) {
        final from = data['from']?.toString();
        final candidate = data['candidate'];
        if (from != null && candidate is Map) {
          debugPrint('Processing ICE candidate from $from');
          await _handleIceCandidate(Map<String, dynamic>.from(candidate));
        }
      } else if (data is Map) {
        debugPrint('Processing legacy ICE candidate');
        await _handleIceCandidate(Map<String, dynamic>.from(data));
      }
    });

    // Handle ICE candidates for room calls
    _socket!.on('roomIceCandidate', (data) async {
      debugPrint('Received room ICE candidate: $data');
      if (data is Map && data['candidate'] != null && data['from'] != null) {
        final from = data['from']?.toString();
        final candidate = data['candidate'];
        if (from != null && candidate is Map) {
          debugPrint('Processing room ICE candidate from $from');
          await _handleRoomIceCandidate(from, Map<String, dynamic>.from(candidate));
        }
      }
    });

    _socket!.on('roomInvite', (data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final isVideo = map['isVideoCall'] == true;
      map['isVideoCall'] = isVideo;
      _roomInviteController.add(map);
    });

    _socket!.on('roomInviteCanceled', (data) {
      if (data is! Map) return;
      _roomInviteController.add({...Map<String, dynamic>.from(data), 'type': 'canceled'});
    });

    _socket!.on('roomInviteDeclined', (data) {
      if (data is! Map) return;
      _roomInviteController.add({...Map<String, dynamic>.from(data), 'type': 'declined'});
    });

    _socket!.on('roomInviteFailed', (data) {
      if (data is! Map) return;
      _roomInviteController.add({...Map<String, dynamic>.from(data), 'type': 'failed'});
    });

    _socket!.on('roomJoined', (data) async {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final rid = map['roomId']?.toString();
      if (rid != null && rid.isNotEmpty) {
        _roomId = rid;
      }

      final isVideo = map['isVideoCall'] == true;
      if (isVideo != _isVideoCall) {
        _isVideoCall = isVideo;
      }

      if (_callState == CallState.idle) {
        _updateCallState(CallState.connecting);
      }

      try {
        await _ensureLocalStream(enableVideo: _isVideoCall);
      } catch (_) {}

      final list = map['participants'];
      if (list is List) {
        _participants
          ..clear()
          ..addAll(list.map((e) => e.toString()));
      }

      // Connect to each participant using deterministic initiator to avoid glare.
      for (final p in _participants) {
        if (p == _currentUserId) continue;
        await _createPeerConnectionFor(p, enableVideo: _isVideoCall);
        if (_shouldInitiateOffer(p)) {
          await _sendRoomOffer(to: p);
        }
      }
    });

    _socket!.on('roomParticipantJoined', (data) async {
      if (data is! Map) return;
      final rid = data['roomId']?.toString();
      final userId = data['userId']?.toString();
      if (rid == null || userId == null) return;
      if (_roomId != null && rid != _roomId) return;
      if (userId == _currentUserId) return;

      _participants.add(userId);
      await _createPeerConnectionFor(userId, enableVideo: _isVideoCall);
      if (_shouldInitiateOffer(userId)) {
        await _sendRoomOffer(to: userId);
      }
    });

    _socket!.on('roomParticipantLeft', (data) async {
      if (data is! Map) return;
      final rid = data['roomId']?.toString();
      final userId = data['userId']?.toString();
      if (rid == null || userId == null) return;
      if (_roomId != null && rid != _roomId) return;
      _participants.remove(userId);

      final pc = _peerConnections.remove(userId);
      if (pc != null) {
        try {
          await pc.close();
          await pc.dispose();
        } catch (_) {}
      }

      final stream = _remoteStreamsByUser.remove(userId);
      if (stream != null) {
        try {
          stream.getTracks().forEach((t) => t.stop());
          await stream.dispose();
        } catch (_) {}
      }
      _remoteStreamsController.add(Map<String, MediaStream>.from(_remoteStreamsByUser));
    });

    _socket!.on('roomSignal', (data) async {
      if (data is! Map) return;
      final rid = data['roomId']?.toString();
      final from = data['from']?.toString();
      final signal = data['signal'];
      if (rid == null || from == null || signal is! Map) return;
      if (_roomId != null && rid != _roomId) return;
      await _handleRoomSignal(from, Map<String, dynamic>.from(signal));
    });

    _socket!.on('roomIceCandidate', (data) async {
      if (data is! Map) return;
      final rid = data['roomId']?.toString();
      final from = data['from']?.toString();
      final candidate = data['candidate'];
      if (rid == null || from == null || candidate is! Map) return;
      if (_roomId != null && rid != _roomId) return;
      await _handleRoomIceCandidate(from, Map<String, dynamic>.from(candidate));
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

    _socket!.on('callCanceled', (data) {
      final from = data is Map ? data['from']?.toString() : null;
      debugPrint('Call canceled by: $from');

      if (_callState == CallState.idle) return;
      if (from != null && from != _remoteUserId) {
        debugPrint('callCanceled from unexpected user ($from); ignoring');
        return;
      }

      SoundManager().stopRingingSound();
      _lastError = 'Call canceled';
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

      if (reason == 'busy') {
        _lastError = 'User is busy';
      } else if (reason == 'offline') {
        _lastError = 'User is offline';
      } else {
        _lastError = 'Call failed';
      }

      SoundManager().playCallEndedSound();
      _endCall();
    });
    
    // Handle connection events
    _socket!.on('connect', (_) {
      debugPrint('Connected to signaling server');
      debugPrint('Emitting register for userId: $_currentUserId');
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

      _remoteStreamsByUser.clear();
      _remoteStreamsController.add({});

      _screenStream?.getTracks().forEach((t) => t.stop());
      await _screenStream?.dispose();
      _screenStream = null;
      _isScreenSharing = false;

      await _peerConnection?.close();
      await _peerConnection?.dispose();
      _peerConnection = null;

      for (final pc in _peerConnections.values) {
        try {
          await pc.close();
          await pc.dispose();
        } catch (_) {}
      }
      _peerConnections.clear();

      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _localStream = null;
      _localStreamController.add(null);

      // Create peer connection with STUN/TURN servers
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {
            'urls': 'stun:stun2.l.google.com:19302',
            'username': '',
            'credential': '',
          },
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turn:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ]
      });
      
      // Set up peer connection event handlers
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        debugPrint('ICE candidate generated');
        _sendIceCandidate(candidate);
      };

      _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
        debugPrint('ICE connection state changed to: $state');
        debugPrint('ICE connection state details: $state');
        if ((_callState == CallState.connecting || _callState == CallState.dialing) &&
            (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateCompleted)) {
          debugPrint('ICE connected - updating call state to connected');
          _updateCallState(CallState.connected);
          SoundManager().playCallConnectedSound();
        }

        if (_callState != CallState.idle &&
            (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
                state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
                state == RTCIceConnectionState.RTCIceConnectionStateClosed)) {
          debugPrint('ICE connection failed/ended with state: $state - failing call');
          _failCall('ice_$state');
        }
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('Peer connection state: $state');
        debugPrint('Peer connection state details: $state');
        if ((_callState == CallState.connecting || _callState == CallState.dialing) &&
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          debugPrint('Peer connection connected - updating call state to connected');
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
        debugPrint('Remote track added - stream count: ${event.streams.length}');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          _remoteStreamController.add(_remoteStream);
          final remoteTrackInfo = _remoteStream!
              .getTracks()
              .map((t) => '${t.kind}(enabled=${t.enabled})')
              .toList();
          debugPrint('Remote tracks: $remoteTrackInfo');
          if (_callState == CallState.connecting) {
            debugPrint('Remote track added while connecting - updating to connected');
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

      // Mirror tracks to any existing room peer connections
      for (final pc in _peerConnections.values) {
        for (final track in _localStream!.getTracks()) {
          try {
            await pc.addTrack(track, _localStream!);
          } catch (_) {}
        }
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
      _roomId = null;
      _participants
        ..clear()
        ..addAll([
          if (_currentUserId != null) _currentUserId!,
          targetUserId,
        ]);
      
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
      _roomId = offerData['roomId']?.toString() ?? _roomId;
      
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
      debugPrint('Sending answer to $from: ${answer.toMap()}');
      _socket!.emit('answerCall', {
        'to': from, // Backend expects 'to'
        'signal': answer.toMap(), // Backend expects 'signal'
        'from': _currentUserId,
        'roomId': _roomId,
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
  Future<void> _handleAnswer(dynamic payload) async {
    try {
      final Map<String, dynamic>? signalData = payload is Map
          ? Map<String, dynamic>.from(payload as Map)
          : null;

      debugPrint('_handleAnswer called with payloadType=${payload.runtimeType} payload=$payload');
      debugPrint('_peerConnection is null: ${_peerConnection == null}');
      debugPrint('_callState: $_callState');

      if (_peerConnection == null) {
        throw Exception('Peer connection is null when handling answer');
      }
      if (signalData == null) {
        throw Exception('Answer payload is not a Map: ${payload.runtimeType}');
      }

      // Cancel dialing timer
      _dialingTimer?.cancel();
      _dialingTimer = null;

      // Update state to connecting
      _updateCallState(CallState.connecting);

      // Handle different possible data structures from backend
      String? sdp;
      String? type;

      debugPrint('Parsing answer data - keys: ${signalData.keys}');

      if (signalData['sdp'] is String && signalData['type'] is String) {
        // Direct structure: {sdp: "...", type: "answer"}
        sdp = signalData['sdp'] as String;
        type = signalData['type'] as String;
      } else if (signalData['signal'] is Map) {
        // Nested structure: {signal: {sdp: "...", type: "answer"}}
        final nested = Map<String, dynamic>.from(signalData['signal'] as Map);
        if (nested['sdp'] is String && nested['type'] is String) {
          sdp = nested['sdp'] as String;
          type = nested['type'] as String;
        }
      }

      if (sdp == null || type == null) {
        throw Exception('Invalid answer payload (missing sdp/type). keys=${signalData.keys} payload=$signalData');
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
        RTCSessionDescription(sdp, type),
      );

      // Caller side: candidates can arrive before the answer. Process buffered candidates now.
      await _processBufferedIceCandidates();

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
    } catch (e, st) {
      _failCall('answer_failed');
      debugPrint('Failed to handle answer: $e\n$st');
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
    
    debugPrint('Sending ICE candidate to $_remoteUserId: ${candidate.toMap()}');
    
    // Use roomIceCandidate when in a room, otherwise use iceCandidate for 1:1
    if (_roomId != null && _roomId!.isNotEmpty) {
      _socket!.emit('roomIceCandidate', {
        'roomId': _roomId,
        'to': _remoteUserId,
        'from': _currentUserId,
        'candidate': candidate.toMap(),
      });
    } else {
      _socket!.emit('iceCandidate', {
        'to': _remoteUserId,
        'from': _currentUserId,
        'candidate': candidate.toMap(),
      });
    }
  }

  Future<void> inviteToCurrentRoom(String callUserId) async {
    final rid = _roomId;
    final me = _currentUserId;
    if (rid == null || rid.isEmpty) {
      throw Exception('No active room to invite into');
    }
    if (me == null) {
      throw Exception('Missing user id');
    }

    _socket?.emit('inviteToRoom', {
      'roomId': rid,
      'to': callUserId,
      'from': me,
    });
  }

  Future<void> acceptRoomInvite(String roomId) async {
    final me = _currentUserId;
    if (me == null) throw Exception('Missing user id');
    _socket?.emit('acceptRoomInvite', {
      'roomId': roomId,
      'from': me,
    });
  }

  void declineRoomInvite(String roomId) {
    final me = _currentUserId;
    if (me == null) return;
    _socket?.emit('declineRoomInvite', {
      'roomId': roomId,
      'from': me,
    });
  }

  void cancelRoomInvite(String roomId, String to) {
    final me = _currentUserId;
    if (me == null) return;
    _socket?.emit('cancelRoomInvite', {
      'roomId': roomId,
      'to': to,
      'from': me,
    });
  }

  Future<void> _sendRoomOffer({required String to}) async {
    final rid = _roomId;
    if (rid == null || rid.isEmpty) return;
    final pc = await _createPeerConnectionFor(to, enableVideo: _isVideoCall);
    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _isVideoCall ? 1 : 0,
    });
    await pc.setLocalDescription(offer);
    _socket?.emit('roomSignal', {
      'roomId': rid,
      'to': to,
      'from': _currentUserId,
      'signal': offer.toMap(),
    });
  }

  Future<void> _handleRoomSignal(String from, Map<String, dynamic> signal) async {
    final type = signal['type']?.toString();
    final sdp = signal['sdp']?.toString();
    if (type == null || sdp == null) return;

    final pc = await _createPeerConnectionFor(from, enableVideo: _isVideoCall);

    if (type == 'offer') {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _processBufferedRoomIce(from);
      final answer = await pc.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _isVideoCall ? 1 : 0,
      });
      await pc.setLocalDescription(answer);
      _socket?.emit('roomSignal', {
        'roomId': _roomId,
        'to': from,
        'from': _currentUserId,
        'signal': answer.toMap(),
      });
      if (_callState == CallState.connecting) {
        _updateCallState(CallState.connected);
        SoundManager().playCallConnectedSound();
      }
    } else if (type == 'answer') {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
      await _processBufferedRoomIce(from);
      if (_callState == CallState.connecting) {
        _updateCallState(CallState.connected);
        SoundManager().playCallConnectedSound();
      }
    }
  }

  Future<void> _handleRoomIceCandidate(
    String from,
    Map<String, dynamic> candidateData,
  ) async {
    final pc = _peerConnections[from];
    if (pc == null) {
      _bufferedRoomIceCandidates.putIfAbsent(from, () => []).add(candidateData);
      return;
    }

    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null) {
      _bufferedRoomIceCandidates.putIfAbsent(from, () => []).add(candidateData);
      return;
    }

    final candidate = candidateData.containsKey('candidate') && candidateData['candidate'] is Map
        ? Map<String, dynamic>.from(candidateData['candidate'] as Map)
        : candidateData;

    final ice = RTCIceCandidate(
      candidate['candidate'],
      candidate['sdpMid'],
      candidate['sdpMLineIndex'],
    );
    await pc.addCandidate(ice);
  }

  Future<void> _processBufferedRoomIce(String from) async {
    final pc = _peerConnections[from];
    if (pc == null) return;
    final list = _bufferedRoomIceCandidates[from];
    if (list == null || list.isEmpty) return;
    for (final c in List<Map<String, dynamic>>.from(list)) {
      try {
        await _handleRoomIceCandidate(from, c);
      } catch (_) {}
    }
    _bufferedRoomIceCandidates[from]?.clear();
  }

  /// End the current call
  void endCall() {
    if (_remoteUserId != null && _socket != null) {
      // If we're still dialing (callee hasn't answered yet), treat this as cancel
      if (_callState == CallState.dialing || _callState == CallState.connecting) {
        _socket!.emit('cancelCall', {
          'to': _remoteUserId,
          'from': _currentUserId,
        });
      } else {
        _socket!.emit('endCall', {
          'to': _remoteUserId,
          'from': _currentUserId,
        });
      }
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
      'error': _lastError,
    });

    if (newState != CallState.idle && _lastError != null) {
      _lastError = null;
    }
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
