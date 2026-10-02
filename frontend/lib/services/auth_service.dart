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

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    accessToken = null;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'password': password,
        }),
      ).timeout(const Duration(seconds: 15));

      // Pass the remaining lock time to the login screen.
      if (response.statusCode == 429) {
        final data = jsonDecode(response.body);

        final seconds = int.tryParse(
          response.headers['retry-after'] ?? '',
        );

        throw AuthException(
          data['detail'] as String? ??
              'Too many failed login attempts.',
          retryAfterSeconds: seconds,
        );
      }

      if (response.statusCode == 401) {
        throw const AuthException('Invalid email or password.');
      }

      if (response.statusCode == 422) {
        throw const AuthException('Please check your email and password.');
      }

      if (response.statusCode != 200) {
        throw const AuthException(
          'Unable to sign in. Please try again later.',
        );
      }

      final data = jsonDecode(response.body);

      // Check the response before accepting the login
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid login response.');
      }

      final token = data['access_token'];
      final user = data['user'];

      if (token is! String ||
          token.isEmpty ||
          user is! Map<String, dynamic>) {
        throw const FormatException('Missing login details.');
      }

      if (user['role'] != 'Admin' && user['role'] != 'Staff') {
        throw const AuthException('This account has an unsupported role.');
      }

      accessToken = token;
      return user;
    } on TimeoutException {
      throw const AuthException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const AuthException(
        'Cannot connect to the server. Check that the backend is running.',
      );
    } on FormatException {
      throw const AuthException(
        'Unexpected server response. Please try again.',
      );
    }
  }

  // Clear the token when logging out
  static void logout() {
    accessToken = null;
  }
}