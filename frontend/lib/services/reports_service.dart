import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

class ReportsService {
  static const Duration _timeout = Duration(seconds: 15);

  static String _date(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static Future<Map<String, dynamic>> fetchSummary({
    DateTime? fromDate,
    DateTime? toDate,
    String? barangay,
  }) async {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw const AuthException('Please log in again.');
    }

    if ((fromDate == null) != (toDate == null)) {
      throw const AuthException('Please select both From Date and To Date.');
    }

    final parameters = <String, String>{};

    if (fromDate != null && toDate != null) {
      parameters['from_date'] = _date(fromDate);
      parameters['to_date'] = _date(toDate);
    }

    if (barangay != null && barangay.trim().isNotEmpty) {
      parameters['barangay'] = barangay.trim();
    }

    final uri = Uri.parse('${AuthService.baseUrl}/reports/summary')
        .replace(queryParameters: parameters.isEmpty ? null : parameters);

    final response = await http
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      String message = 'Unable to load reports.';

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final detail = decoded['detail'];
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
        // Retain default error.
      }

      if (response.statusCode == 401) {
        message = 'Your session has expired. Please log in again.';
      } else if (response.statusCode == 403) {
        message = 'You are not authorized to access reports.';
      }

      throw AuthException(message);
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic> ||
        decoded['totals'] is! Map ||
        decoded['barangays'] is! List) {
      throw const FormatException('Invalid reports response from FastAPI.');
    }

    return decoded;
  }
}
