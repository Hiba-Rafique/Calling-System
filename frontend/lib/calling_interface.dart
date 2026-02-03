import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'call_service.dart';
import 'sound_manager.dart';

/// Full-screen calling interface with visual feedback
class CallingInterface extends StatefulWidget {
  final String targetUserId;
  final String? primaryBaseUrl;
  final String? fallbackBaseUrl;
  final bool isIncoming;
  final Function() onCallEnd;

  const CallingInterface({
    super.key,
    required this.targetUserId,
    this.primaryBaseUrl,
    this.fallbackBaseUrl,
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
  final TextEditingController _inviteController = TextEditingController();

  Box<dynamic>? _contactsBox;
  List<Map<String, dynamic>> _contacts = const [];
  String? _selectedContactCallId;

  Timer? _inviteSearchDebounce;
  bool _isInviteSearching = false;
  List<Map<String, dynamic>> _inviteSearchResults = const [];
  String? _inviteSearchError;
  bool _isDisposed = false;
  bool _isSpeakerOn = false;
  bool _isMuted = false;
  bool _isCameraOn = false;
  bool _isScreenSharing = false;
  Duration _callDuration = Duration.zero;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize state from CallService
    _isSpeakerOn = _callService.isSpeakerOn;
    _isMuted = _callService.isMuted;
    _isCameraOn = _callService.isCameraOn;
    _isScreenSharing = _callService.isScreenSharing;
    
    _initializeRenderer();
    _setupAnimations();
    _initInviteContacts();
  }

  Future<void> _initInviteContacts() async {
    try {
      if (!Hive.isBoxOpen('contacts')) {
        _contactsBox = await Hive.openBox<dynamic>('contacts');
      } else {
        _contactsBox = Hive.box<dynamic>('contacts');
      }
      _loadInviteContactsFromCache();
    } catch (_) {}
  }

  void _loadInviteContactsFromCache() {
    final box = _contactsBox;
    if (box == null) return;
    final list = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        final callId = (map['call_user_id'] ?? map['display'] ?? '').toString().trim();
        if (callId.isEmpty) continue;
        list.add(map);
      }
    }
    list.sort((a, b) {
      final an = (a['display'] ?? a['call_user_id'] ?? '').toString().toLowerCase();
      final bn = (b['display'] ?? b['call_user_id'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    if (mounted) {
      setState(() {
        _contacts = list;
      });
    }
  }

  Future<void> _initializeRenderer() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
    
    if (!_isDisposed) {
      _remoteRenderer.srcObject = _callService.remoteStream;
      _localRenderer.srcObject = _callService.localStream;
    }

    _callService.remoteStreamStream.listen((stream) {
      if (_isDisposed) return;
      _remoteRenderer.srcObject = stream;
      if (mounted) {
        setState(() {});
      }
    });

    _callService.remoteStreamsStream.listen((streams) {
      if (_isDisposed) return;
      // For audio-only calls, ensure the first remote stream is attached to enable audio playback
      if (!_callService.isVideoCall && streams.isNotEmpty) {
        final firstRemoteStream = streams.values.first;
        _remoteRenderer.srcObject = firstRemoteStream;
        debugPrint('🔊 Attached first remote stream to renderer for audio-only call');
      }
      if (mounted) setState(() {});
    });

    _callService.localStreamStream.listen((stream) {
      if (_isDisposed) return;
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
    _isDisposed = true;
    _inviteSearchDebounce?.cancel();
    _inviteController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  Uri _uri(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: path);
  }

  Future<String?> _getToken() async {
    try {
      final authBox = Hive.box<dynamic>('auth');
      final token = authBox.get('auth_token');
      return token is String ? token : null;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> _withFallback(
    Future<http.Response> Function(String baseUrl) request,
  ) async {
    final primary = widget.primaryBaseUrl;
    final fallback = widget.fallbackBaseUrl;
    if (primary == null || primary.isEmpty || fallback == null || fallback.isEmpty) {
      return request(primary ?? fallback ?? '').timeout(const Duration(seconds: 6));
    }

    try {
      final res = await request(primary).timeout(const Duration(seconds: 6));
      if (res.statusCode >= 500) {
        return request(fallback).timeout(const Duration(seconds: 6));
      }
      return res;
    } catch (_) {
      return request(fallback).timeout(const Duration(seconds: 6));
    }
  }

  void _onInviteSearchChanged(String value) {
    _inviteSearchDebounce?.cancel();
    _inviteSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchInviteUsers(value);
    });
  }

  Future<void> _searchInviteUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _inviteSearchResults = const [];
          _inviteSearchError = null;
          _isInviteSearching = false;
        });
      }
      return;
    }

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _inviteSearchResults = const [];
          _inviteSearchError = 'Missing session';
        });
      }
      return;
    }

    setState(() {
      _isInviteSearching = true;
      _inviteSearchError = null;
    });

    try {
      final res = await _withFallback(
        (url) => http.get(
          _uri(url, '/api/users/search').replace(queryParameters: {'q': q}),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (mounted) {
          setState(() {
            _inviteSearchResults = const [];
            _inviteSearchError = 'Search failed (${res.statusCode})';
          });
        }
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return;

      final results = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final callId = (map['call_user_id'] ?? '').toString().trim();
          if (callId.isEmpty) continue;
          results.add({
            'call_user_id': callId,
            'first_name': map['first_name'],
            'last_name': map['last_name'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _inviteSearchResults = results;
          _inviteSearchError = results.isEmpty ? 'No matches' : null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inviteSearchResults = const [];
          _inviteSearchError = 'Search failed';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInviteSearching = false;
        });
      }
    }
  }

  Future<void> _promptInvite() async {
    if (_callService.callState != CallState.connected) return;

    _inviteController.clear();
    _selectedContactCallId = null;
    if (mounted) {
      setState(() {
        _inviteSearchResults = const [];
        _inviteSearchError = null;
        _isInviteSearching = false;
      });
    }

    final target = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        String? chosen;
        bool useContacts = true;
        String? selectedContact;

        return StatefulBuilder(
          builder: (ctx2, setLocal) {
            final bottomInset = MediaQuery.of(ctx2).viewInsets.bottom;
            final contacts = _contacts;

            List<Map<String, dynamic>> filteredContacts = contacts;
            final query = _inviteController.text.trim().toLowerCase();
            if (useContacts && query.isNotEmpty) {
              filteredContacts = contacts.where((c) {
                final display = (c['display'] ?? c['call_user_id'] ?? '').toString().toLowerCase();
                final callId = (c['call_user_id'] ?? '').toString().toLowerCase();
                return display.contains(query) || callId.contains(query);
              }).toList();
            }

            final canInvite = (chosen ?? _inviteController.text).trim().isNotEmpty;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(ctx2).size.height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Add person',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx2).pop(),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _inviteController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            labelText: 'Search contacts or users',
                            hintText: 'Enter Call ID',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (v) {
                            chosen = v.trim();
                            if (!useContacts) {
                              _onInviteSearchChanged(v);
                            }
                            setLocal(() {});
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.people_alt),
                              label: Text('Contacts'),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.public),
                              label: Text('Search'),
                            ),
                          ],
                          selected: {useContacts},
                          onSelectionChanged: (s) {
                            useContacts = s.first;
                            selectedContact = null;
                            _selectedContactCallId = null;
                            chosen = _inviteController.text.trim();
                            if (!useContacts) {
                              _onInviteSearchChanged(_inviteController.text);
                            }
                            setLocal(() {});
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Material(
                            color: Colors.transparent,
                            child: ListView(
                              children: [
                                if (useContacts) ...[
                                  if (filteredContacts.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No contacts found'),
                                    ),
                                  for (final c in filteredContacts)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          final callId = (c['call_user_id'] ?? c['display'] ?? '').toString().trim();
                                          if (callId.isEmpty) return;
                                          selectedContact = callId;
                                          _selectedContactCallId = callId;
                                          chosen = callId;
                                          _inviteController.text = callId;
                                          setLocal(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: selectedContact == (c['call_user_id'] ?? c['display'])
                                                ? Theme.of(ctx2).colorScheme.primary.withOpacity(0.12)
                                                : Theme.of(ctx2).colorScheme.surface,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Theme.of(ctx2).dividerColor.withOpacity(0.2),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                child: Text(
                                                  ((c['display'] ?? c['call_user_id'] ?? 'U').toString())
                                                      .trim()
                                                      .toUpperCase()
                                                      .substring(0, 1),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      (c['display'] ?? c['call_user_id'] ?? '').toString(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      (c['call_user_id'] ?? '').toString(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Theme.of(ctx2).textTheme.bodySmall?.color,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (selectedContact == (c['call_user_id'] ?? c['display']))
                                                Icon(Icons.check_circle, color: Theme.of(ctx2).colorScheme.primary),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ] else ...[
                                  if (_isInviteSearching)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: LinearProgressIndicator(minHeight: 2),
                                    ),
                                  if (_inviteSearchError != null)
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(_inviteSearchError!),
                                    ),
                                  if (_inviteSearchResults.isEmpty && !_isInviteSearching && (_inviteController.text.trim().isNotEmpty))
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No matches'),
                                    ),
                                  for (final u in _inviteSearchResults)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () {
                                          final callId = (u['call_user_id'] ?? '').toString().trim();
                                          if (callId.isEmpty) return;
                                          chosen = callId;
                                          _inviteController.text = callId;
                                          setLocal(() {});
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Theme.of(ctx2).colorScheme.surface,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: Theme.of(ctx2).dividerColor.withOpacity(0.2),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                child: Text(
                                                  ((u['first_name'] ?? 'U').toString()).trim().isNotEmpty
                                                      ? (u['first_name'] as Object).toString().trim().toUpperCase().substring(0, 1)
                                                      : 'U',
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      ('${(u['first_name'] ?? '').toString()} ${(u['last_name'] ?? '').toString()}').trim().isEmpty
                                                          ? (u['call_user_id'] ?? '').toString()
                                                          : ('${(u['first_name'] ?? '').toString()} ${(u['last_name'] ?? '').toString()}').trim(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      (u['call_user_id'] ?? '').toString(),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Theme.of(ctx2).textTheme.bodySmall?.color,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        child: FilledButton.icon(
                          onPressed: canInvite
                              ? () {
                                  Navigator.of(ctx2).pop((chosen ?? _inviteController.text).trim());
                                }
                              : null,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Invite'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (target == null || target.isEmpty) return;
 
    try {
      await _callService.inviteToCurrentRoom(target);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited $target')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
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
    final screenSize = MediaQuery.of(context).size;
    final localPreviewWidth = (screenSize.width * 0.30).clamp(96.0, 160.0);
    final localPreviewHeight = (screenSize.height * 0.25).clamp(128.0, 220.0);
    final isInVideoConnected =
        _callService.isVideoCall && _callService.callState == CallState.connected;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
            if (_callService.isVideoCall)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  mirror: false,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                ),
              )
            else
              // Audio-only calls still require attaching the remote stream to a media element
              // (especially on web) to allow audio playback.
              Positioned(
                left: 0,
                top: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: Opacity(
                    opacity: 0.0,
                    child: RTCVideoView(
                      _remoteRenderer,
                      mirror: false,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                    ),
                  ),
                ),
              ),

            if (_callService.isVideoCall)
              Positioned(
                right: 16,
                top: 80,
                width: localPreviewWidth,
                height: localPreviewHeight,
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
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
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
                  if (!isInVideoConnected) ...[
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
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _callService.isScreenSharing
                                      ? Icons.screen_share
                                      : Icons.videocam,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _callService.isScreenSharing
                                      ? 'Screen'
                                      : 'Video',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: StreamBuilder<Duration>(
                              stream: _callService.callDurationStream,
                              initialData: _callService.callDuration,
                              builder: (context, snapshot) {
                                final duration = snapshot.data ?? Duration.zero;
                                return Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Text(
                              widget.targetUserId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
                  
                  // Call controls
                  Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 24,
                    ),
                    decoration: BoxDecoration(
                      color: (_callService.isVideoCall)
                          ? Colors.black.withOpacity(0.35)
                          : Colors.transparent,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        if (_callService.callState == CallState.connected)
                          _buildControlButton(
                            icon: Icons.person_add,
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _promptInvite();
                            },
                            backgroundColor: Colors.grey[800]!,
                          ),

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

                        if (_callService.callState == CallState.connected &&
                            _callService.isVideoCall)
                          _buildControlButton(
                            icon: _callService.isScreenSharing
                                ? Icons.stop_screen_share
                                : Icons.screen_share,
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              try {
                                if (_callService.isScreenSharing) {
                                  await _callService.stopScreenShare();
                                } else {
                                  await _callService.startScreenShare();
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              }
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
