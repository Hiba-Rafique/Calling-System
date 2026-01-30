import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'set_call_id_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String primaryBaseUrl;
  final String fallbackBaseUrl;

  const ProfileScreen({
    super.key,
    required this.primaryBaseUrl,
    required this.fallbackBaseUrl,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();

  bool _isLoading = true;
  Map<String, dynamic>? _me;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cached = await _auth.getCachedMe();
      if (mounted) {
        setState(() {
          _me = cached;
        });
      }

      final token = await _auth.getToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Missing session';
          });
        }
        return;
      }

      try {
        final refreshed = await _auth.me(baseUrl: widget.primaryBaseUrl, token: token);
        if (mounted) {
          setState(() {
            _me = refreshed;
          });
        }
      } catch (_) {
        final refreshed = await _auth.me(baseUrl: widget.fallbackBaseUrl, token: token);
        if (mounted) {
          setState(() {
            _me = refreshed;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _editCallId() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SetCallIdScreen(baseUrl: widget.primaryBaseUrl),
      ),
    );

    final newId = result?.trim();
    if (newId == null || newId.isEmpty) return;

    if (!mounted) return;
    Navigator.of(context).pop(newId);
  }

  String _fullName(Map<String, dynamic>? me) {
    final first = (me?['first_name'] ?? '').toString().trim();
    final last = (me?['last_name'] ?? '').toString().trim();
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Your Profile' : name;
  }

  String _createdAt(Map<String, dynamic>? me) {
    final raw = (me?['created_at'] ?? '').toString().trim();
    if (raw.isEmpty) return '-';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final name = _fullName(me);
    final email = (me?['email'] ?? '-').toString();
    final callId = (me?['call_user_id'] ?? '-').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Card(
                        color: Colors.red[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red[800]),
                          ),
                        ),
                      ),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              child: Text(
                                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.alternate_email),
                            title: const Text('Call ID'),
                            subtitle: Text(callId),
                            trailing: const Icon(Icons.edit),
                            onTap: _editCallId,
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.mail_outline),
                            title: const Text('Email'),
                            subtitle: Text(email),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(Icons.calendar_today_outlined),
                            title: const Text('Joined'),
                            subtitle: Text(_createdAt(me)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
