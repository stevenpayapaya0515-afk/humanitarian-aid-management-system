import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/reports_service.dart';

class StaffReportScreen extends StatefulWidget {
  final String heading;

  const StaffReportScreen({super.key, this.heading = 'Staff Reports'});

  @override
  State<StaffReportScreen> createState() => _StaffReportScreenState();
}

class _StaffReportScreenState extends State<StaffReportScreen> {
  final _barangayController = TextEditingController();

  DateTime? _fromDate;
  DateTime? _toDate;
  Map<String, dynamic>? _report;

  bool _isLoading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void dispose() {
    _barangayController.dispose();
    super.dispose();
  }

  // ==========================================
  // HELPERS
  // ==========================================

  String _date(DateTime? date) {
    if (date == null) return 'Select date';

    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  int _count(dynamic value) {
    return value is num ? value.toInt() : 0;
  }

  String _errorMessage(Object error) {
    if (error is AuthException) return error.message;

    if (error is TimeoutException) {
      return 'The server took too long to respond.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to FastAPI. Check your backend.';
    }

    if (error is FormatException) {
      return 'Invalid response from the server.';
    }

    return 'Unable to load the report. Please try again.';
  }

  // ==========================================
  // SUCCESS AND ERROR MODALS
  // ==========================================

  Future<void> _showFeedback({
    required bool success,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              size: 58,
              color: success ? AppColors.primaryGreen : const Color(0xFFC62828),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.greyText),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 44),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // LOADING MODAL
  // ==========================================

  void _showLoadingDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.white,
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primaryGreen),
                SizedBox(height: 18),
                Text(
                  'Generating Report...',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Loading report totals from FastAPI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.greyText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // FETCH REPORT FROM FASTAPI
  // ==========================================

  Future<void> _loadReport({
    bool showSuccess = false,
    bool showError = false,
  }) async {
    if (_isLoading || !mounted) return;

    if ((_fromDate == null) != (_toDate == null) ||
        (_fromDate != null &&
            _toDate != null &&
            _fromDate!.isAfter(_toDate!))) {
      await _showFeedback(
        success: false,
        title: 'Invalid Date Range',
        message: 'Select both dates, with From Date on or before To Date.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    if (showSuccess) {
      _showLoadingDialog();
    }

    bool loaded = false;
    String? errorMessage;

    try {
      final result = await ReportsService.fetchSummary(
        fromDate: _fromDate,
        toDate: _toDate,
        barangay: _barangayController.text,
      );

      if (!mounted) return;

      setState(() {
        _report = result;
      });

      loaded = true;
    } catch (error) {
      errorMessage = _errorMessage(error);

      if (mounted) {
        setState(() {
          _loadError = errorMessage;
        });
      }
    } finally {
      if (mounted) {
        if (showSuccess) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        setState(() {
          _isLoading = false;
        });
      }
    }

    if (!mounted) return;

    if (!loaded && (showSuccess || showError)) {
      await _showFeedback(
        success: false,
        title: 'Report Not Loaded',
        message: errorMessage ?? 'Please try again.',
      );
    } else if (loaded && showSuccess) {
      await _showFeedback(
        success: true,
        title: 'Report Generated',
        message:
            'The report has been updated using '
            'the latest saved records.',
      );
    }
  }

  // ==========================================
  // DATE FILTERS
  // ==========================================

  Future<void> _pickDate({required bool from}) async {
    final selected = from ? _fromDate : _toDate;
    final today = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: selected ?? today,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: from ? 'Select From Date' : 'Select To Date',
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (from) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  void _clearFilters() {
    if (_isLoading) return;

    setState(() {
      _fromDate = null;
      _toDate = null;
      _barangayController.clear();
    });

    _loadReport(showError: true);
  }

  // ==========================================
  // REFRESH BUTTON
  // ==========================================

  Widget _refreshButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: _isLoading ? null : () => _loadReport(showError: true),
        borderRadius: BorderRadius.circular(24),
        hoverColor: const Color(0xFFE5E7EB),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryGreen,
                  ),
                )
              else
                const Icon(
                  Icons.refresh,
                  size: 18,
                  color: AppColors.primaryGreen,
                ),
              const SizedBox(width: 8),
              Text(
                _isLoading ? 'Refreshing...' : 'Refresh report',
                style: const TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // REUSABLE SECTION
  // ==========================================

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = constraints.maxWidth < 520;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, color: AppColors.primaryGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.greyText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!mobile && trailing != null) trailing,
                ],
              ),
              if (mobile && trailing != null) ...[
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
              const SizedBox(height: 18),
              child,
            ],
          );
        },
      ),
    );
  }

  Widget _dateButton(String label, DateTime? value, VoidCallback onTap) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
        ),
        child: Row(
          children: [
            Expanded(child: Text(_date(value))),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // REPORT FILTERS
  // ==========================================

  Widget _filterSection() {
    return _section(
      title: 'Report Filters',
      subtitle:
          'Dates filter household registration dates '
          '(Philippine time).',
      icon: Icons.filter_alt_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;

          final fieldWidth = narrow
              ? constraints.maxWidth
              : (constraints.maxWidth - 32) / 3;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _dateButton(
                      'Registered from',
                      _fromDate,
                      () => _pickDate(from: true),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _dateButton(
                      'Registered through',
                      _toDate,
                      () => _pickDate(from: false),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _barangayController,
                      enabled: !_isLoading,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Barangay (optional)',
                        hintText: 'Search barangay name',
                        prefixIcon: Icon(Icons.search),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _loadReport(showSuccess: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _loadReport(showSuccess: true),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.assessment_outlined, size: 18),
                    label: Text(
                      _isLoading ? 'Generating...' : 'Generate Report',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _clearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Clear Filters'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryGreen,
                      side: const BorderSide(color: AppColors.primaryGreen),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // SUMMARY CARDS
  // ==========================================

  Widget _metricCard(String label, int value, IconData icon, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryGreen, size: 22),
          const SizedBox(height: 13),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _totalsSection(Map<String, dynamic> totals) {
    const fields = <(String, String, IconData)>[
      ('Total Households', 'total_households', Icons.home_outlined),
      ('Total Population', 'total_population', Icons.people_outline),
      ('Assessed Households', 'assessed_households', Icons.assignment_outlined),
      (
        'Classified Households',
        'classified_households',
        Icons.analytics_outlined,
      ),
      ('Low Vulnerability', 'low_vulnerability', Icons.trending_down_outlined),
      (
        'Medium Vulnerability',
        'medium_vulnerability',
        Icons.trending_flat_outlined,
      ),
      (
        'High Vulnerability',
        'high_vulnerability',
        Icons.warning_amber_outlined,
      ),
      (
        'Pending Beneficiaries',
        'pending_beneficiaries',
        Icons.hourglass_empty_outlined,
      ),
      ('For Review', 'for_review_beneficiaries', Icons.rate_review_outlined),
      (
        'Approved Beneficiaries',
        'approved_beneficiaries',
        Icons.verified_outlined,
      ),
      (
        'Rejected Beneficiaries',
        'rejected_beneficiaries',
        Icons.block_outlined,
      ),
      (
        'Recorded Deliveries',
        'aid_distributions',
        Icons.inventory_2_outlined,
      ),
    ];

    return _section(
      title: 'Report Summary',
      subtitle:
          'Current household and beneficiary totals '
          'for the selected filters.',
      icon: Icons.bar_chart_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final columns = width >= 850
              ? 4
              : width >= 510
              ? 2
              : 1;

          final cardWidth = (width - (columns - 1) * 12) / columns;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in fields)
                _metricCard(
                  item.$1,
                  _count(totals[item.$2]),
                  item.$3,
                  cardWidth,
                ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // BARANGAY REPORT TABLE
  // ==========================================

  Widget _barangayTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            'No barangay records match these filters.',
            style: TextStyle(color: AppColors.greyText),
          ),
        ),
      );
    }

    const columns = <(String, String)>[
      ('Barangay', 'barangay'),
      ('Households', 'total_households'),
      ('Population', 'total_population'),
      ('Assessed', 'assessed_households'),
      ('Classified', 'classified_households'),
      ('Low', 'low_vulnerability'),
      ('Medium', 'medium_vulnerability'),
      ('High', 'high_vulnerability'),
      ('Pending', 'pending_beneficiaries'),
      ('For Review', 'for_review_beneficiaries'),
      ('Approved', 'approved_beneficiaries'),
      ('Rejected', 'rejected_beneficiaries'),
      ('Deliveries', 'aid_distributions'),
      ('Practice entries', 'simulated_distributions'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(AppColors.lightGreen),
        columnSpacing: 22,
        columns: [for (final item in columns) DataColumn(label: Text(item.$1))],
        rows: rows.map((row) {
          return DataRow(
            cells: [
              for (final item in columns)
                DataCell(
                  Text(
                    item.$2 == 'barangay'
                        ? '${row['barangay'] ?? '—'}'
                        : '${_count(row[item.$2])}',
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ==========================================
  // MAIN SCREEN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final report = _report;

    final totals = report?['totals'] is Map
        ? Map<String, dynamic>.from(report!['totals'] as Map)
        : <String, dynamic>{};

    final barangays = report?['barangays'] is List
        ? (report!['barangays'] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList()
        : <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.heading,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'View household, vulnerability, beneficiary, '
          'and distribution summaries.',
          style: TextStyle(fontSize: 13, color: AppColors.greyText),
        ),
        const SizedBox(height: 18),

        // ======================================
        // TESTING MODE NOTICE
        // ======================================
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: AppColors.primaryGreen),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delivery totals exclude practice entries. '
                  'Classifications support staff review.',
                  style: TextStyle(fontSize: 12, color: AppColors.darkText),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        _filterSection(),
        const SizedBox(height: 20),

        if (_loadError != null) ...[
          Text(_loadError!, style: const TextStyle(color: Color(0xFFC62828))),
          const SizedBox(height: 12),
        ],

        // ======================================
        // LOADING / EMPTY / RESULTS
        // ======================================
        if (_isLoading && report == null)
          const Padding(
            padding: EdgeInsets.all(38),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            ),
          )
        else if (report != null) ...[
          _section(
            title: 'Report Information',
            subtitle: 'Filters currently applied to the displayed report.',
            icon: Icons.info_outline,
            trailing: _refreshButton(),
            child: Text(
              'Registration dates: '
              '${report['from_date'] ?? 'All dates'}'
              ' to ${report['to_date'] ?? 'All dates'}  •  '
              'Barangay: '
              '${report['barangay_filter'] ?? 'All barangays'}',
              style: const TextStyle(color: AppColors.greyText, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          _totalsSection(totals),
          const SizedBox(height: 20),
          _section(
            title: 'Barangay Breakdown',
            subtitle:
                '${barangays.length} barangay report rows. '
                'Scroll horizontally to see all columns.',
            icon: Icons.location_city_outlined,
            child: _barangayTable(barangays),
          ),
        ] else if (!_isLoading)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Center(child: Text('No report is available yet.')),
          ),

        const SizedBox(height: 20),

        const Text(
          'Date filters select households by registration '
          'date in Philippine time. Assessments, classifications, '
          'beneficiary statuses, and distribution counts are current '
          'values for those households.',
          style: TextStyle(fontSize: 11, color: AppColors.greyText),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}
