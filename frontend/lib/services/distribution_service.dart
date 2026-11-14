import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class DistributionService {
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

  static void _checkResponse(http.Response response, int expectedCode) {
    if (response.statusCode == expectedCode) return;

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
      // Use the default error message.
    }

    if (response.statusCode == 401) {
      message = 'Session expired. Please log in again.';
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

  // Load beneficiaries approved for distribution.
  static Future<List<Map<String, dynamic>>> fetchBeneficiaries() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/distributions/beneficiaries'),
          headers: _headers(),
        )
        .timeout(_timeout);

    _checkResponse(response, 200);
    return _decodeList(response);
  }

  // Load saved distribution records.
  static Future<List<Map<String, dynamic>>> fetchDistributions() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/distributions'),
          headers: _headers(),
        )
        .timeout(_timeout);

    _checkResponse(response, 200);
    return _decodeList(response);
  }

  // Create a new distribution record.
  static Future<Map<String, dynamic>> createDistribution({
    required int beneficiaryId,
    required String aidType,
    required int quantity,
    required String unit,
    required String distributionDate,
    required String batchCode,
    required String notes,
    required int expectedAssessmentId,
    required int expectedClassificationId,
    required bool deliveryConfirmed,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/distributions'),
          headers: _headers(),
          body: jsonEncode({
            'beneficiary_id': beneficiaryId,
            'expected_assessment_id': expectedAssessmentId,
            'expected_classification_id': expectedClassificationId,
            'delivery_confirmed': deliveryConfirmed,
            'aid_type': aidType,
            'quantity': quantity,
            'unit': unit,
            'distribution_date': distributionDate,
            'batch_code': batchCode.trim().toUpperCase(),
            'notes': notes.trim(),
          }),
        )
        .timeout(_timeout);

    _checkResponse(response, 201);
    return _decodeObject(response);
  }
}
