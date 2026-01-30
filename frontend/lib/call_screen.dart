import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'call_service.dart';
import 'calling_interface.dart';
import 'sound_manager.dart';

/// Main calling screen with UI for making and receiving calls
class CallScreen extends StatefulWidget {
  final String userId;
  final String primaryBaseUrl;
  final String fallbackBaseUrl;

  const CallScreen({
    super.key,
    required this.userId,
    required this.primaryBaseUrl,
    required this.fallbackBaseUrl,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  final TextEditingController _targetUserIdController = TextEditingController();
  Box<dynamic>? _contactsBox;
  dynamic _contacts = const [];
  bool _isSyncingContacts = false;
  Timer? _searchDebounce;
  bool _isSearchingUsers = false;
  List<Map<String, dynamic>> _searchResults = const [];
  String? _searchError;
  
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
    _initContacts();
  }

  Future<void> _searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _isSearchingUsers = false;
          _searchError = null;
        });
      }
      return;
    }

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchError = 'Missing session';
        });
      }
      return;
    }

    setState(() {
      _isSearchingUsers = true;
      _searchError = null;
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
        final snippet = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
        debugPrint('User search failed status=${res.statusCode} body=$snippet');
        if (mounted) {
          setState(() {
            _searchResults = const [];
            _searchError = res.statusCode == 401
                ? 'Session expired'
                : 'Search failed (${res.statusCode})';
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
            'user_id': map['user_id'],
            'first_name': map['first_name'],
            'last_name': map['last_name'],
          });
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _searchError = results.isEmpty ? 'No matches' : null;
        });
      }
    } catch (_) {
      debugPrint('User search request failed');
      if (mounted) {
        setState(() {
          _searchResults = const [];
          _searchError = 'Search failed';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingUsers = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchUsers(value);
    });
  }

  bool _isAlreadyInContacts(String callId) {
    final existing = _contactsAsMaps();
    for (final c in existing) {
      final existingCallId = (c['call_user_id'] ?? c['display'] ?? '').toString().trim();
      if (existingCallId.isNotEmpty && existingCallId.toLowerCase() == callId.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _targetUserIdController.dispose();
    super.dispose();
  }

  Future<void> _initContacts() async {
    try {
      if (!Hive.isBoxOpen('contacts')) {
        _contactsBox = await Hive.openBox<dynamic>('contacts');
      } else {
        _contactsBox = Hive.box<dynamic>('contacts');
      }
      _loadContactsFromCache();
      await _syncContactsFromServer();
    } catch (_) {
    }
  }

  List<Map<String, dynamic>> _contactsAsMaps() {
    final val = _contacts;
    if (val is List<Map<String, dynamic>>) return val;

    if (val is List) {
      final converted = <Map<String, dynamic>>[];
      for (final item in val) {
        if (item is Map) {
          converted.add(Map<String, dynamic>.from(item));
        } else if (item is String) {
          final id = item.trim();
          if (id.isNotEmpty) {
            converted.add({
              'contact_id': null,
              'contact_user_id': null,
              'call_user_id': id,
              'display': id,
              'nickname': null,
            });
          }
        }
      }
      return converted;
    }

    return const <Map<String, dynamic>>[];
  }

  void _loadContactsFromCache() {
    final box = _contactsBox;
    if (box == null) return;
    final list = <Map<String, dynamic>>[];
    bool needsMigration = false;
    final legacyStrings = <String>[];

    for (final key in box.keys) {
      final val = box.get(key);
      if (val is Map) {
        final map = Map<String, dynamic>.from(val);
        list.add(map);
        continue;
      }

      if (val is String) {
        needsMigration = true;
        legacyStrings.add(val);
        continue;
      }

      if (val is List) {
        needsMigration = true;
        for (final item in val) {
          if (item is String) {
            legacyStrings.add(item);
          }
        }
        continue;
      }
    }

    if (needsMigration) {
      final unique = <String>{};
      for (final s in legacyStrings) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty) {
          unique.add(trimmed);
        }
      }

      final migrated = unique
          .map<Map<String, dynamic>>(
            (id) => {
              'contact_id': null,
              'contact_user_id': null,
              'call_user_id': id,
              'display': id,
              'nickname': null,
            },
          )
          .toList();

      list
        ..clear()
        ..addAll(migrated);

      try {
        box.clear();
        for (var i = 0; i < migrated.length; i++) {
          box.put('legacy_$i', migrated[i]);
        }
      } catch (_) {
      }
    }

    list.sort((a, b) {
      final an = (a['display'] ?? '').toString().toLowerCase();
      final bn = (b['display'] ?? '').toString().toLowerCase();
      return an.compareTo(bn);
    });
    if (mounted) {
      setState(() {
        _contacts = list;
      });
    }
  }

  Uri _uri(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: path);
  }

  Future<http.Response> _withFallback(
    Future<http.Response> Function(String baseUrl) request,
  ) async {
    try {
      return await request(widget.primaryBaseUrl).timeout(const Duration(seconds: 6));
    } catch (_) {
      return request(widget.fallbackBaseUrl).timeout(const Duration(seconds: 6));
    }
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

  Future<void> _syncContactsFromServer() async {
    final token = await _getToken();
    if (token == null || token.isEmpty) return;

    setState(() {
      _isSyncingContacts = true;
    });

    try {
      final res = await _withFallback(
        (url) => http.get(
          _uri(url, '/api/contacts'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) return;

      final serverContacts = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final callId = (map['call_user_id'] ?? '').toString().trim();
          final display = callId.isNotEmpty
              ? callId
              : (map['contact_user_id'] ?? '').toString();
          serverContacts.add({
            'contact_id': map['contact_id'],
            'contact_user_id': map['contact_user_id'],
            'call_user_id': map['call_user_id'],
            'display': display,
            'nickname': map['nickname'],
          });
        }
      }

      final box = _contactsBox;
      if (box != null) {
        await box.clear();
        for (final c in serverContacts) {
          await box.put(c['contact_id'].toString(), c);
        }
      }

      _loadContactsFromCache();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingContacts = false;
        });
      }
    }
  }

  Future<void> _addContactFromInput() async {
    final callId = _targetUserIdController.text.trim();
    if (callId.isEmpty) return;
    if (callId == widget.userId) {
      _showErrorDialog('You cannot add yourself');
      return;
    }

    final token = await _getToken();
    if (token == null || token.isEmpty) {
      _showErrorDialog('Missing session. Please login again.');
      return;
    }

    try {
      final res = await _withFallback(
        (url) => http.post(
          _uri(url, '/api/contacts'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'contact_call_id': callId,
          }),
        ),
      );

      if (res.statusCode == 409) {
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showErrorDialog('Failed to add contact');
        return;
      }

      await _syncContactsFromServer();
    } catch (_) {
      _showErrorDialog('Failed to add contact (offline)');
    }
  }

  Future<void> _removeContact(Map<String, dynamic> contact) async {
    final contactId = contact['contact_id'];
    if (contactId == null) return;
    final token = await _getToken();
    if (token == null || token.isEmpty) return;

    try {
      final res = await _withFallback(
        (url) => http.delete(
          _uri(url, '/api/contacts/$contactId'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return;
      }

      final box = _contactsBox;
      if (box != null) {
        await box.delete(contactId.toString());
      }
      _loadContactsFromCache();
    } catch (_) {
    }
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
    final contacts = _contactsAsMaps();

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
      ),
      body: Column(
        children: [
          if (_isSyncingContacts)
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.white10,
              color: Theme.of(context).colorScheme.primary,
            ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _targetUserIdController,
                      decoration: InputDecoration(
                        labelText: 'Enter user id to call',
                        hintText: 'Enter user id to call',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      textInputAction: TextInputAction.go,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) => _makeCall(video: false),
                    ),

                    if (_isSearchingUsers)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),

                    if (_searchError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _searchError!,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                    if (_searchResults.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          children: _searchResults.map((u) {
                            final callId = (u['call_user_id'] ?? '').toString();
                            final name = '${(u['first_name'] ?? '').toString()} ${(u['last_name'] ?? '').toString()}'.trim();
                            final isContact = _isAlreadyInContacts(callId);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text(callId, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: name.isEmpty ? null : Text(name),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isContact)
                                      IconButton(
                                        tooltip: 'Add contact',
                                        onPressed: () async {
                                          _targetUserIdController.text = callId;
                                          await SoundManager().vibrateOnce();
                                          await _addContactFromInput();
                                        },
                                        icon: const Icon(Icons.person_add_alt_1),
                                      ),
                                    IconButton(
                                      tooltip: 'Voice call',
                                      onPressed: () async {
                                        _targetUserIdController.text = callId;
                                        await SoundManager().vibrateOnce();
                                        await _makeCall(video: false);
                                      },
                                      icon: const Icon(Icons.call, color: Colors.green),
                                    ),
                                    IconButton(
                                      tooltip: 'Video call',
                                      onPressed: () async {
                                        _targetUserIdController.text = callId;
                                        await SoundManager().vibrateOnce();
                                        await _makeCall(video: true);
                                      },
                                      icon: const Icon(Icons.videocam, color: Colors.blue),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  _targetUserIdController.text = callId;
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                  ],
                ),
              ),
            ),
          ),

          if (contacts.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No contacts yet',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                itemCount: contacts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final c = contacts[index];
                  final id = (c['display'] ?? '').toString();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          id.isNotEmpty ? id.substring(0, 1).toUpperCase() : '?',
                        ),
                      ),
                      title: Text(
                        id,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Tap an icon to call',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Voice call',
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              _targetUserIdController.text = id;
                              await _makeCall(video: false);
                            },
                            icon: const Icon(Icons.call, color: Colors.green),
                          ),
                          IconButton(
                            tooltip: 'Video call',
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              _targetUserIdController.text = id;
                              await _makeCall(video: true);
                            },
                            icon: const Icon(Icons.videocam, color: Colors.blue),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () async {
                              await SoundManager().vibrateOnce();
                              await _removeContact(c);
                            },
                            icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      onTap: () {
                        _targetUserIdController.text = id;
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
