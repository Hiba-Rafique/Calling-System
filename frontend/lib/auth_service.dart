import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive/hive.dart';

class AuthService {
  static const String _boxName = 'auth';
  static const String _tokenKey = 'auth_token';
  static const String _meKey = 'auth_me';
  static const String _defaultFallbackBaseUrl = 'http://localhost:5000';

  Box<dynamic> _box() {
    return Hive.box<dynamic>(_boxName);
  }

  Future<void> saveToken(String token) async {
    await _box().put(_tokenKey, token);
  }

  Future<String?> getToken() async {
    final token = _box().get(_tokenKey);
    return token is String ? token : null;
  }

  Future<void> clearToken() async {
    await _box().delete(_tokenKey);
    await _box().delete(_meKey);
  }

  Future<void> saveMe(Map<String, dynamic> me) async {
    await _box().put(_meKey, me);
  }

  Future<Map<String, dynamic>?> getCachedMe() async {
    final val = _box().get(_meKey);
    if (val is Map) {
      return Map<String, dynamic>.from(val);
    }
    return null;
  }

  Uri _uri(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: path);
  }

  Map<String, dynamic> _tryDecodeJsonObject(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw Exception('Expected JSON object');
    } catch (_) {
      final snippet = res.body.length > 200 ? res.body.substring(0, 200) : res.body;
      throw Exception(
        'Invalid server response (status ${res.statusCode}). Body: $snippet',
      );
    }
  }

  Future<http.Response> _withFallback(
    Future<http.Response> Function(String baseUrl) request, {
    required String primaryBaseUrl,
    String fallbackBaseUrl = _defaultFallbackBaseUrl,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final res = await request(primaryBaseUrl).timeout(timeout);
      if (res.statusCode >= 500) {
        return request(fallbackBaseUrl).timeout(timeout);
      }
      return res;
    } on TimeoutException {
      return request(fallbackBaseUrl).timeout(timeout);
    } on SocketException {
      return request(fallbackBaseUrl).timeout(timeout);
    } on http.ClientException {
      return request(fallbackBaseUrl).timeout(timeout);
    } catch (e) {
      if (e.toString().contains('XMLHttpRequest') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('NetworkError')) {
        return request(fallbackBaseUrl).timeout(timeout);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register({
    required String baseUrl,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    final res = await _withFallback(
      (url) => http.post(
        _uri(url, '/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'password': password,
        }),
      ),
      primaryBaseUrl: baseUrl,
    );

    final Map<String, dynamic> body = _tryDecodeJsonObject(res);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Registration failed');
    }

    return body;
  }

  Future<Map<String, dynamic>> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    debugPrint('Attempting login to: $baseUrl');
    try {
      final res = await _withFallback(
        (url) {
          debugPrint('Sending login request to: $url');
          return http.post(
            _uri(url, '/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          );
        },
        primaryBaseUrl: baseUrl,
      );

      debugPrint('Login response status: ${res.statusCode}');
      debugPrint('Login response body: ${res.body}');

      final Map<String, dynamic> body = _tryDecodeJsonObject(res);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(body['error'] ?? 'Login failed');
      }

      final token = body['token'];
      if (token is String && token.isNotEmpty) {
        await saveToken(token);
        debugPrint('Token saved successfully');
      }

      return body;
    } catch (e) {
      debugPrint('Login error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> me({
    required String baseUrl,
    required String token,
  }) async {
    final res = await _withFallback(
      (url) => http.get(
        _uri(url, '/api/me'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
      primaryBaseUrl: baseUrl,
    );

    final Map<String, dynamic> body = _tryDecodeJsonObject(res);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Session expired');
    }

    await saveMe(body);
    return body;
  }

  Future<Map<String, dynamic>> setCallUserId({
    required String baseUrl,
    required String callUserId,
  }) async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      throw Exception('Missing auth token');
    }

    final res = await _withFallback(
      (url) => http.post(
        _uri(url, '/api/me/call-user-id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'call_user_id': callUserId}),
      ),
      primaryBaseUrl: baseUrl,
    );

    final Map<String, dynamic> body = _tryDecodeJsonObject(res);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Failed to set Call ID');
    }

    await saveMe(body);

    return body;
  }

  Future<void> registerFcmToken({
    required String baseUrl,
    required String authToken,
    required String fcmToken,
  }) async {
    final t = fcmToken.trim();
    if (t.isEmpty) {
      throw Exception('FCM token is empty');
    }

    final res = await _withFallback(
      (url) => http.post(
        _uri(url, '/api/push/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({'token': t}),
      ),
      primaryBaseUrl: baseUrl,
    );

    final Map<String, dynamic> body = _tryDecodeJsonObject(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Failed to register FCM token');
    }
  }
}
