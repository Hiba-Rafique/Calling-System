import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _defaultFallbackBaseUrl = 'http://localhost:5000';

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
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
  }) async {
    try {
      return await request(primaryBaseUrl);
    } on SocketException {
      return request(fallbackBaseUrl);
    } on http.ClientException {
      return request(fallbackBaseUrl);
    } catch (e) {
      if (e.toString().contains('XMLHttpRequest') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('Connection refused') ||
          e.toString().contains('NetworkError')) {
        return request(fallbackBaseUrl);
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
    final res = await _withFallback(
      (url) => http.post(
        _uri(url, '/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ),
      primaryBaseUrl: baseUrl,
    );

    final Map<String, dynamic> body = _tryDecodeJsonObject(res);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(body['error'] ?? 'Login failed');
    }

    final token = body['token'];
    if (token is String && token.isNotEmpty) {
      await saveToken(token);
    }

    return body;
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

    return body;
  }
}
