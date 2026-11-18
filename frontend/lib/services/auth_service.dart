import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'session_storage_stub.dart' if (dart.library.js_interop) 'session_storage_web.dart' as tab_store;

class AuthException implements Exception {
  final String message;

  // Remaining lock time supplied by the backend.
  final int? retryAfterSeconds;

  const AuthException(this.message, {this.retryAfterSeconds});

  @override
  String toString() => message;
}

class AuthService {
  // Override for Android: --dart-define=AIDTRACK_API_BASE_URL=http://LAPTOP_IP:8000
  // Flutter Web on this computer continues to use localhost by default.
  static const String baseUrl = String.fromEnvironment(
    'AIDTRACK_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  // Keep the token in memory during this app session
  static String? accessToken;

  // A browser refresh resets Dart memory. This saves the session only for
  // the current browser tab, and the backend verifies it on every reload.
  static const _tokenKey = 'aidtrack.session.jwt';
  static const _roleKey = 'aidtrack.session.role';
  static const _pageKey = 'aidtrack.session.page';
  static String? _role;
  static String _page = 'Dashboard';

  static String initialPageForRole(String role) {
    const adminPages = <String>{
      'Dashboard', 'Household Records', 'Household Assessment',
      'Vulnerability Classification', 'Beneficiary Management',
      'Aid Distribution', 'Reports', 'User Management', 'Settings',
    };
    const staffPages = <String>{
      'Dashboard', 'Household Registration', 'Household Assessment',
      'Vulnerability Classification', 'Beneficiary Management',
      'Aid Distribution', 'Reports', 'Settings',
    };
    final allowed = role == 'Admin' ? adminPages : staffPages;
    return _role == role && allowed.contains(_page) ? _page : 'Dashboard';
  }

  static void rememberPage(String role, String page) {
    if (accessToken == null || _role != role) return;
    _page = initialAllowedPage(role, page);
    tab_store.write(_pageKey, _page);
  }

  static String initialAllowedPage(String role, String page) {
    const adminPages = <String>{
      'Dashboard', 'Household Records', 'Household Assessment',
      'Vulnerability Classification', 'Beneficiary Management',
      'Aid Distribution', 'Reports', 'User Management', 'Settings',
    };
    const staffPages = <String>{
      'Dashboard', 'Household Registration', 'Household Assessment',
      'Vulnerability Classification', 'Beneficiary Management',
      'Aid Distribution', 'Reports', 'Settings',
    };
    return (role == 'Admin' ? adminPages : staffPages).contains(page)
        ? page
        : 'Dashboard';
  }

  static void _saveVerifiedSession(String token, String role) {
    accessToken = token;
    _role = role;
    _page = 'Dashboard';
    tab_store.write(_tokenKey, token);
    tab_store.write(_roleKey, role);
    tab_store.write(_pageKey, _page);
  }

  static Future<String?> restoreSession() async {
    final storedToken = tab_store.read(_tokenKey);
    if (storedToken == null || storedToken.isEmpty) return null;

    // Authenticate with FastAPI; never trust role/page values in browser storage.
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $storedToken',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 401 || response.statusCode == 403) {
      logout();
      return null;
    }
    if (response.statusCode != 200) {
      throw const AuthException('Cannot verify session right now.');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        (data['role'] != 'Admin' && data['role'] != 'Staff')) {
      logout();
      return null;
    }

    final validRole = data['role'] as String;
    final previousRole = tab_store.read(_roleKey);
    accessToken = storedToken;
    _role = validRole;
    _page = previousRole == validRole
        ? initialAllowedPage(validRole, tab_store.read(_pageKey) ?? 'Dashboard')
        : 'Dashboard';
    tab_store.write(_roleKey, validRole);
    tab_store.write(_pageKey, _page);
    return validRole;
  }


  static Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/$path');
      final response =
          await (body == null
                  ? http.get(uri)
                  : http.post(
                      uri,
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode(body),
                    ))
              .timeout(const Duration(seconds: 60));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw AuthException(
          data is Map && data['detail'] is String
              ? data['detail'] as String
              : 'Please check your entries and try again.',
          retryAfterSeconds: int.tryParse(
            response.headers['retry-after'] ?? '',
          ),
        );
      }
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }
      return data;
    } on TimeoutException {
      throw const AuthException('The server took too long. Please try again.');
    } on http.ClientException {
      throw const AuthException(
        'Cannot connect. Check that the backend is running.',
      );
    } on FormatException {
      throw const AuthException(
        'Unexpected server response. Please try again.',
      );
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    logout();
    final data = await _request(
      'login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    );
    if (data['challenge_id'] is! String || data['expires_at'] is! String) {
      throw const AuthException('Unexpected login response. Please try again.');
    }
    return data;
  }

  static Future<Map<String, dynamic>> verifyOtp(
    String challengeId,
    String code,
  ) async {
    logout();
    final data = await _request(
      'verify-otp',
      body: {'challenge_id': challengeId, 'code': code.trim()},
    );
    final token = data['access_token'];
    final user = data['user'];
    if (token is! String || token.isEmpty || user is! Map<String, dynamic>) {
      throw const AuthException(
        'Unexpected verification response. Please sign in again.',
      );
    }
    if (user['role'] != 'Admin' && user['role'] != 'Staff') {
      throw const AuthException('This account has an unsupported role.');
    }
    _saveVerifiedSession(token, user['role'] as String);
    return user;
  }

  // Clear the token when logging out
  static void logout() {
    accessToken = null;
    _role = null;
    _page = 'Dashboard';
    tab_store.remove(_tokenKey);
    tab_store.remove(_roleKey);
    tab_store.remove(_pageKey);
  }
}
