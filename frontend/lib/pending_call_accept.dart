import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingCallAccept {
  static const _prefsName = 'incoming_call_prefs';
  static const _keyPendingAccept = 'pending_accept';

  static Future<Map<String, dynamic>?> consume() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPendingAccept);
    if (raw == null || raw.isEmpty) return null;

    try {
      final map = jsonDecode(raw);
      if (map is! Map) {
        await prefs.remove(_keyPendingAccept);
        return null;
      }

      final m = Map<String, dynamic>.from(map);
      final ts = (m['ts'] is num) ? (m['ts'] as num).toInt() : 0;
      final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
      if (ts <= 0 || ageMs > 90 * 1000) {
        await prefs.remove(_keyPendingAccept);
        return null;
      }

      await prefs.remove(_keyPendingAccept);
      return m;
    } catch (_) {
      await prefs.remove(_keyPendingAccept);
      return null;
    }
  }
}
