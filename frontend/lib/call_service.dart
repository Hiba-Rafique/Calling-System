import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'sound_manager.dart';

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
  
  // User information
  String? _currentUserId;
  String? _remoteUserId;
  String? _callId;
  Timer? _dialingTimer;
  
  // Call state
  CallState _callState = CallState.idle;
  final StreamController<Map<String, dynamic>> _callStateController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _incomingCallController = StreamController.broadcast();
  
  // ICE candidate buffering
  final List<Map<String, dynamic>> _bufferedIceCandidates = [];
  
  // Stream controllers for UI updates
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  
  // Getters for streams
  Stream<Map<String, dynamic>> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;
  
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

  /// Initialize the service with user ID and connect to signaling server
  Future<void> initialize(String userId, {String serverUrl = kSignalingServerUrl}) async {
    _currentUserId = userId;
    
    // Connect to Socket.IO server
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    
    // Set up Socket.IO event listeners
    _setupSocketListeners();
    
    // Initialize WebRTC
    await _initializeWebRTC();
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
      debugPrint('Call ended by: ${data['from']}');
      _endCall();
    });
    
    // Handle call rejected
    _socket!.on('callRejected', (data) {
      debugPrint('Call rejected by: ${data['from']}');
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
    });
  }

  /// Initialize WebRTC peer connection and local media stream
  Future<void> _initializeWebRTC() async {
    try {
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
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        debugPrint('Peer connection state: $state');
        if ((_callState == CallState.connecting || _callState == CallState.dialing) &&
            state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _updateCallState(CallState.connected);
          SoundManager().playCallConnectedSound();
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
      }

      // Get local audio stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      
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

  /// Initiate a call to another user
  Future<void> callUser(String targetUserId) async {
    if (_callState != CallState.idle && _callState != CallState.ringing) {
      throw Exception('Already in a call');
    }
    
    if (_peerConnection == null) {
      throw Exception('WebRTC not initialized');
    }
    
    try {
      _remoteUserId = targetUserId;
      _callId = '${_currentUserId}_$targetUserId';
      
      // Update state to dialing
      _updateCallState(CallState.dialing);
      
      // Play dialing sound
      await SoundManager().playDialingSound();
      
      // Start dialing timer for timeout
      _dialingTimer = Timer(Duration(seconds: 30), () {
        if (_callState == CallState.dialing) {
          _endCall();
        }
      });
      
      // Create offer
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
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
      _remoteUserId = from;
      _callId = callId;
      
      // Update state to connecting
      _updateCallState(CallState.connecting);
      
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
        'offerToReceiveVideo': 0,
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
          await Helper.setSpeakerphoneOn(true);
        } catch (e) {
          debugPrint('Audio route setup failed: $e');
        }
      }
      
      debugPrint('Call accepted from: $from');
    } catch (e) {
      _updateCallState(CallState.idle);
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
          await Helper.setSpeakerphoneOn(true);
        } catch (e) {
          debugPrint('Audio route setup failed: $e');
        }
      }
      
      debugPrint('Call answered successfully');
    } catch (e) {
      _updateCallState(CallState.idle);
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
    // Note: Backend doesn't have explicit end call handling
    // Just end the call locally
    _endCall();
  }

  /// Internal method to clean up call state
  void _endCall() {
    // Cancel any timers
    _dialingTimer?.cancel();
    _dialingTimer = null;
    
    // Stop all sounds
    SoundManager().stopAll();
    
    // Play call ended sound if we were in a call
    if (_callState == CallState.connected || _callState == CallState.dialing) {
      SoundManager().playCallEndedSound();
    }
    
    _updateCallState(CallState.idle);
    _remoteUserId = null;
    _callId = null;
    
    debugPrint('Call ended');
  }
  
  /// Update call state and notify listeners
  void _updateCallState(CallState newState) {
    _callState = newState;
    _callStateController.add({
      'callState': _callState,
      'remoteUserId': _remoteUserId,
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
    
    SoundManager().dispose();
    
    debugPrint('CallService disposed');
  }
}
