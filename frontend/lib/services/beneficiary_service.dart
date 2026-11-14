import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class BeneficiaryService {
  static const Duration _timeout = Duration(seconds: 15);

  static Map<String, String> _headers() {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw const AuthException('Please log in again.');
    }

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static void _checkResponse(http.Response response, int expectedStatus) {
    if (response.statusCode == expectedStatus) return;

    String message = 'Request failed (${response.statusCode}).';

    try {
      final data = jsonDecode(response.body);

      if (data is Map<String, dynamic>) {
        final detail = data['detail'];

        if (detail is String) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty) {
          final first = detail.first;

          if (first is Map && first['msg'] is String) {
            message = first['msg'] as String;
          }
        }
      }
    } catch (_) {
      // Keep the default message.
    }

    if (response.statusCode == 401) {
      message = 'Your session has expired. Please log in again.';
    } else if (response.statusCode == 403) {
      message = 'You are not authorized to perform this action.';
    }

    throw AuthException(message);
  }

  static List<Map<String, dynamic>> _decodeList(http.Response response) {
    final data = jsonDecode(response.body);

    if (data is! List) {
      throw const FormatException('Invalid list response.');
    }

    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  static Map<String, dynamic> _decodeObject(http.Response response) {
    final data = jsonDecode(response.body);

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid server response.');
    }

    return data;
  }

  // Get households available for beneficiary review.
  static Future<List<Map<String, dynamic>>> fetchCandidates() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/beneficiaries/candidates'),
          headers: _headers(),
        )
        .timeout(_timeout);

    _checkResponse(response, 200);
    return _decodeList(response);
  }

  // Retrieve existing beneficiary records.
  static Future<List<Map<String, dynamic>>> fetchBeneficiaries() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/beneficiaries'),
          headers: _headers(),
        )
        .timeout(_timeout);

    _checkResponse(response, 200);
    return _decodeList(response);
  }

  // Register a household for manual review.
  static Future<Map<String, dynamic>> createBeneficiary({
    required int householdId,
    required String reviewNotes,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/beneficiaries'),
          headers: _headers(),
          body: jsonEncode({
            'household_id': householdId,
            'review_notes': reviewNotes,
          }),
        )
        .timeout(_timeout);

    _checkResponse(response, 201);
    return _decodeObject(response);
  }

  // Update the manual review status.
  static Future<Map<String, dynamic>> updateBeneficiary({
    required int beneficiaryId,
    required String status,
    required String reviewNotes,
    required int expectedAssessmentId,
    required int expectedClassificationId,
    required String expectedStatus,
    required bool reviewConfirmed,
  }) async {
    final response = await http
        .patch(
          Uri.parse('${AuthService.baseUrl}/beneficiaries/$beneficiaryId'),
          headers: _headers(),
          body: jsonEncode({
            'status': status, 'review_notes': reviewNotes,
            'expected_assessment_id': expectedAssessmentId,
            'expected_classification_id': expectedClassificationId,
            'expected_status': expectedStatus, 'review_confirmed': reviewConfirmed,
          }),
        )
        .timeout(_timeout);

    _checkResponse(response, 200);
    return _decodeObject(response);
  }

  static Future<void> useLatestAssessment(Map<String, dynamic> record) async {
    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}/beneficiaries/${record['beneficiary_id']}/use-latest-assessment'),
      headers: _headers(),
      body: jsonEncode({
        'expected_assessment_id': record['assessment_id'],
        'expected_classification_id': record['classification_id'],
      }),
    ).timeout(_timeout);
    _checkResponse(response, 200);
  }

  // Retrieve the audit history of status changes.
  static Future<List<Map<String, dynamic>>> fetchHistory(
    int beneficiaryId,
  ) async {
    final response = await http
        .get(
          Uri.parse(
            '${AuthService.baseUrl}/beneficiaries/$beneficiaryId/history',
          ),
          headers: _headers(),
        )
        .timeout(_timeout);

    _checkResponse(response, 200);
    return _decodeList(response);
  }
}
