import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;


class AuthException implements Exception {
  final String message;

  // Remaining lock time supplied by the backend.
  final int? retryAfterSeconds;

  const AuthException(
    this.message, {
    this.retryAfterSeconds,
  });

  @override
  String toString() => message;
}


class AuthService {
  // Local backend for Flutter Web on the same computer
  static const String baseUrl = 'http://127.0.0.1:8000';

  // Keep the token in memory during this app session
  static String? accessToken;

  static Future<Map<String, dynamic>> _request(
    String path, {Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/$path');
      final response = await (body == null
          ? http.get(uri)
          : http.post(uri, headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))).timeout(const Duration(seconds: 60));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw AuthException(
          data is Map && data['detail'] is String
              ? data['detail'] as String : 'Please check your entries and try again.',
          retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? ''),
        );
      }
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }
      return data;
    } on TimeoutException {
      throw const AuthException('The server took too long. Please try again.');
    } on http.ClientException {
      throw const AuthException('Cannot connect. Check that the backend is running.');
    } on FormatException {
      throw const AuthException('Unexpected server response. Please try again.');
    }
  }

  static Future<Map<String, dynamic>> captcha() => _request('captcha');

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String captchaId,
    required String captchaAnswer,
  }) async {
    accessToken = null;
    final data = await _request('login', body: {
      'email': email.trim().toLowerCase(), 'password': password,
      'captcha_id': captchaId, 'captcha_answer': captchaAnswer.trim(),
    });
    if (data['challenge_id'] is! String || data['expires_at'] is! String) {
      throw const AuthException('Unexpected login response. Please try again.');
    }
    return data;
  }

  static Future<Map<String, dynamic>> verifyOtp(String challengeId, String code) async {
    accessToken = null;
    final data = await _request('verify-otp', body: {
      'challenge_id': challengeId, 'code': code.trim(),
    });
    final token = data['access_token'];
    final user = data['user'];
    if (token is! String || token.isEmpty || user is! Map<String, dynamic>) {
      throw const AuthException('Unexpected verification response. Please sign in again.');
    }
    if (user['role'] != 'Admin' && user['role'] != 'Staff') {
      throw const AuthException('This account has an unsupported role.');
    }
    accessToken = token;
    return user;
  }

  // Clear the token when logging out
  static void logout() {
    accessToken = null;
  }
}