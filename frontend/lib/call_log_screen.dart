import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

class CallLogScreen extends StatefulWidget {
  final String primaryBaseUrl;
  final String fallbackBaseUrl;

  const CallLogScreen({
    super.key,
    required this.primaryBaseUrl,
    required this.fallbackBaseUrl,
  });

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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

  Future<http.Response> _getWithFallback(
    String path, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      return await http
          .get(_uri(widget.primaryBaseUrl, path), headers: headers)
          .timeout(timeout);
    } on TimeoutException {
      return http
          .get(_uri(widget.fallbackBaseUrl, path), headers: headers)
          .timeout(timeout);
    } catch (_) {
      return http
          .get(_uri(widget.fallbackBaseUrl, path), headers: headers)
          .timeout(timeout);
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _error = 'Missing session. Please login again.';
          _rows = const [];
        });
        return;
      }

      final res = await _getWithFallback(
        '/api/calls',
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        Map<String, dynamic>? err;
        try {
          final decoded = jsonDecode(res.body);
          if (decoded is Map) {
            err = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
        throw Exception(err?['error'] ?? 'Failed to load call log');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception('Invalid server response');
      }

      final list = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          list.add(Map<String, dynamic>.from(item));
        }
      }

      if (mounted) {
        setState(() {
          _rows = list;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _rows = const [];
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'completed':
        return Icons.call_made;
      case 'missed':
        return Icons.call_missed;
      default:
        return Icons.call;
    }
  }

  Color _colorForStatus(BuildContext context, String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'missed':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _subtitle(Map<String, dynamic> row) {
    final status = (row['call_status'] ?? '').toString();
    final started = (row['started_at'] ?? '').toString();
    final ended = (row['ended_at'] ?? '').toString();
    final startedDate = started.length >= 16 ? started.substring(0, 16) : started;
    final endedDate = ended.length >= 16 ? ended.substring(0, 16) : ended;

    if (status == 'completed' && endedDate.isNotEmpty) {
      return 'Ended: $endedDate';
    }
    if (startedDate.isNotEmpty) {
      return 'Started: $startedDate';
    }
    return status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Log'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(12),
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
                      )
                    else if (_rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(child: Text('No calls yet')),
                      )
                    else
                      ..._rows.map((r) {
                        final status = (r['call_status'] ?? '').toString();
                        final caller = (r['caller_call_user_id'] ?? r['caller_id'] ?? '-').toString();
                        final receiver = (r['receiver_call_user_id'] ?? r['receiver_id'] ?? '-').toString();

                        return Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _colorForStatus(context, status).withOpacity(0.12),
                              child: Icon(
                                _iconForStatus(status),
                                color: _colorForStatus(context, status),
                              ),
                            ),
                            title: Text('$caller → $receiver'),
                            subtitle: Text(_subtitle(r)),
                            trailing: Text(status),
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}
