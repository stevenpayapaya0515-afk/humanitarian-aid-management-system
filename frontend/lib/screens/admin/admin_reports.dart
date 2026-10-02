import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

// ========================================
// ADMIN HOUSEHOLD REGISTRATION REPORT
// ========================================

class AdminReports extends StatefulWidget {
  const AdminReports({super.key});

  @override
  State<AdminReports> createState() => _AdminReportsState();
}

class _AdminReportsState extends State<AdminReports> {
  // Individual records used for date filtering and barangay totals.
  List<Map<String, dynamic>> _households = [];

  bool _isLoading = true;
  String? _error;
  String _searchText = '';

  // Calendar selections.
  DateTime? _fromDate;
  DateTime? _toDate;

  // Dates currently applied to the report.
  DateTime? _appliedFromDate;
  DateTime? _appliedToDate;

  String? _filterError;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  // ========================================
  // DATE HELPERS
  // ========================================

  // Display the date as YYYY-MM-DD.
  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  // Convert a registration timestamp into its Philippine calendar date.
  DateTime _registrationDate(Map<String, dynamic> household) {
    final timestamp = DateTime.parse(
      household['created_at'] as String,
    );

    final philippineTime = timestamp.toUtc().add(
      const Duration(hours: 8),
    );

    return DateTime(
      philippineTime.year,
      philippineTime.month,
      philippineTime.day,
    );
  }

  // Open the calendar for From Date or To Date.
  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 8),
    );

    final today = DateTime(now.year, now.month, now.day);
    final selected = isFrom ? _fromDate : _toDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: selected ?? today,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: isFrom ? 'Select From Date' : 'Select To Date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }

      _filterError = null;
    });
  }

  // Apply the selected dates after checking their order.
  void _applyDateFilter() {
    if (_fromDate == null || _toDate == null) {
      setState(() {
        _filterError = 'Please select both From Date and To Date.';
      });
      return;
    }

    if (_fromDate!.isAfter(_toDate!)) {
      setState(() {
        _filterError = 'From Date must be on or before To Date.';
      });
      return;
    }

    setState(() {
      _appliedFromDate = _fromDate;
      _appliedToDate = _toDate;
      _filterError = null;
    });
  }

  // Clear dates while keeping the barangay search.
  void _clearDateFilter() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _appliedFromDate = null;
      _appliedToDate = null;
      _filterError = null;
    });
  }

  // ========================================
  // LOAD HOUSEHOLD RECORDS
  // ========================================

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final token = AuthService.accessToken;

      if (token == null || token.isEmpty) {
        throw const AuthException('Please log in again.');
      }

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/households'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw const AuthException(
          'Your session has expired. Please log out and log in again.',
        );
      }

      if (response.statusCode == 403) {
        throw const AuthException(
          'Your account cannot access these records.',
        );
      }

      if (response.statusCode != 200) {
        throw const AuthException(
          'Unable to load the report. Please try again.',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw const FormatException('Invalid household response.');
      }

      final records = <Map<String, dynamic>>[];

      for (final item in decoded) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid household record.');
        }

        final barangay = item['barangay'];
        final size = item['household_size'];
        final createdAt = item['created_at'];

        // Check the values needed for the report.
        if (barangay is! String ||
            barangay.trim().isEmpty ||
            size is! int ||
            size < 1 ||
            createdAt is! String) {
          throw const FormatException('Invalid household details.');
        }

        // Backend timestamps must include a timezone.
        final timestamp = DateTime.tryParse(createdAt);

        if (timestamp == null || !timestamp.isUtc) {
          throw const FormatException('Invalid registration timestamp.');
        }

        records.add(Map<String, dynamic>.from(item));
      }

      if (!mounted) return;

      setState(() {
        _households = records;
      });
    } catch (error) {
      if (!mounted) return;

      final String message;

      if (error is AuthException) {
        message = error.message;
      } else if (error is TimeoutException) {
        message = 'Loading timed out. Please click Refresh.';
      } else if (error is http.ClientException) {
        message = 'Cannot connect to the server. Check your backend.';
      } else {
        message = 'Unable to read household records. Please try again.';
      }

      setState(() {
        _error = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ========================================
  // FILTER AND GROUP RECORDS
  // ========================================

  List<Map<String, dynamic>> _groupFilteredHouseholds() {
    final grouped = <String, Map<String, dynamic>>{};

    for (final household in _households) {
      final registeredDate = _registrationDate(household);

      // Include the entire first and last selected days.
      if (_appliedFromDate != null &&
          registeredDate.isBefore(_appliedFromDate!)) {
        continue;
      }

      if (_appliedToDate != null &&
          registeredDate.isAfter(_appliedToDate!)) {
        continue;
      }

      // Combine names with different capitalization or extra spaces.
      final name = (household['barangay'] as String)
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');

      final key = name.toLowerCase();

      grouped.putIfAbsent(
        key,
        () => {
          'barangay': name,
          'households': 0,
          'population': 0,
        },
      );

      // Count each household once.
      grouped[key]!['households'] =
          (grouped[key]!['households'] as int) + 1;

      // Household size includes the household head.
      grouped[key]!['population'] =
          (grouped[key]!['population'] as int) +
              (household['household_size'] as int);
    }

    // Arrange barangays alphabetically.
    return grouped.values.toList()
      ..sort(
        (a, b) => (a['barangay'] as String)
            .toLowerCase()
            .compareTo((b['barangay'] as String).toLowerCase()),
      );
  }

  // ========================================
  // DATE FILTER CONTROLS
  // ========================================

  Widget _buildDateFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Registration Date',
          style: TextStyle(
            color: AppColors.primaryGreen,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 10),

        // Wrap the buttons when the screen is narrow.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: true),
              icon: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
              ),
              label: Text(
                _fromDate == null
                    ? 'From Date'
                    : 'From: ${_formatDate(_fromDate!)}',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                minimumSize: const Size(160, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            OutlinedButton.icon(
              onPressed: () => _pickDate(isFrom: false),
              icon: const Icon(
                Icons.calendar_today_outlined,
                size: 18,
              ),
              label: Text(
                _toDate == null
                    ? 'To Date'
                    : 'To: ${_formatDate(_toDate!)}',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                minimumSize: const Size(160, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _applyDateFilter,
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Apply Filter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(140, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            TextButton(
              onPressed: _clearDateFilter,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
              ),
              child: const Text('Clear Dates'),
            ),
          ],
        ),

        if (_filterError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _filterError!,
              style: const TextStyle(color: Colors.red),
            ),
          ),

        const SizedBox(height: 12),

        // Show the dates actually applied to the displayed report.
        Text(
          _appliedFromDate == null
              ? 'Showing: All registration dates'
              : 'Showing: ${_formatDate(_appliedFromDate!)}'
                  ' to ${_formatDate(_appliedToDate!)} (Philippine time)',
          style: const TextStyle(
            color: AppColors.greyText,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ========================================
  // REPORT TABLE
  // ========================================

  Widget _buildReportTable(List<Map<String, dynamic>> rows) {
    // Calculate totals for the displayed barangays only.
    final totalHouseholds = rows.fold<int>(
      0,
      (total, row) => total + (row['households'] as int),
    );

    final totalPopulation = rows.fold<int>(
      0,
      (total, row) => total + (row['population'] as int),
    );

    const totalStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: AppColors.primaryGreen,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
            ),
            child: DataTable(
              columnSpacing: 24,
              horizontalMargin: 12,
              columns: const [
                DataColumn(
                  label: Text('Barangay'),
                ),
                DataColumn(
                  label: Text('Registered Households'),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('Total Household Population'),
                  numeric: true,
                ),
              ],
              rows: [
                // One row for each matching barangay.
                for (final row in rows)
                  DataRow(
                    cells: [
                      DataCell(Text('${row['barangay']}')),
                      DataCell(Text('${row['households']}')),
                      DataCell(Text('${row['population']}')),
                    ],
                  ),

                // Combined totals for the displayed rows.
                DataRow(
                  cells: [
                    const DataCell(
                      Text('TOTAL', style: totalStyle),
                    ),
                    DataCell(
                      Text('$totalHouseholds', style: totalStyle),
                    ),
                    DataCell(
                      Text('$totalPopulation', style: totalStyle),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ========================================
  // MAIN REPORT SCREEN
  // ========================================

  // AdminDashboard provides the surrounding page and vertical scrolling.
  @override
  Widget build(BuildContext context) {
    final barangayRows = _groupFilteredHouseholds();
    final query = _searchText.trim().toLowerCase();

    // Search barangay results after applying registration dates.
    final filtered = barangayRows.where((row) {
      return (row['barangay'] as String)
          .toLowerCase()
          .contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ========================================
        // REPORT HEADING OUTSIDE THE WHITE BOX
        // ========================================

        Row(
          children: [
            const Expanded(
              child: Text(
                'Household Registration Report',
                style: TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Reload the report using the existing function.
            IconButton(
              tooltip: 'Refresh report',
              onPressed: _isLoading ? null : _loadReport,
              icon: const Icon(
                Icons.refresh,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        const Text(
          'Current registered households and household population '
          'grouped by barangay.',
          style: TextStyle(
            color: AppColors.greyText,
          ),
        ),

        const SizedBox(height: 20),

        // ========================================
        // WHITE BOX: FILTERS, SEARCH, AND TABLE
        // ========================================

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE0E7E2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // From Date, To Date, Apply Filter, and Clear Dates.
              _buildDateFilters(),

              const SizedBox(height: 20),

              // Search works together with the applied date filter.
              TextField(
                onChanged: (value) {
                  setState(() {
                    _searchText = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search barangay...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFFF5F8F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Show the loading, error, or result state.
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                )
              else if (_households.isEmpty)
                const Text('No household records available yet.')
              else if (barangayRows.isEmpty)
                const Text(
                  'No households were registered within the selected dates.',
                )
              else if (filtered.isEmpty)
                const Text('No barangays match your search.')
              else ...[
                Text(
                  '${filtered.length} barangay(s) shown',
                  style: const TextStyle(
                    color: AppColors.greyText,
                  ),
                ),

                const SizedBox(height: 12),

                // Display the existing report table and totals.
                _buildReportTable(filtered),
              ],
            ],
          ),
        ),
      ],
    );
  }
  }