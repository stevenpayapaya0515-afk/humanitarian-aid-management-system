import '../../widgets/aidtrack_section_card.dart';

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'report_document.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/reports_service.dart';
import '../../widgets/aidtrack_module_loading.dart';

class StaffReportScreen extends StatefulWidget {
  final String heading;
  final bool showHeading;

  const StaffReportScreen({
    super.key,
    this.heading = 'Reports',
    this.showHeading = true,
  });

  @override
  State<StaffReportScreen> createState() => _StaffReportScreenState();
}

class _StaffReportScreenState extends State<StaffReportScreen> {
  static const columns = <(String, String)>[
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
  final _chartKey = GlobalKey();
  bool _exporting = false;
  String _barangay = '';
  final _barangayOptions = <String>{
    for (var i = 1; i <= 12; i++) 'Poblacion $i',
    'Antonio Luna', 'Bay-ang', 'Bayabas', 'Caasinan', 'Cabinet', 'Calamba',
    'Calibunan', 'Comagascas', 'Concepcion', 'Del Pilar', 'Katugasan',
    'Kauswagan', 'La Union', 'Mabini', 'Mahaba', 'Puting Bato', 'Sanghan',
    'Soriano', 'Tolosa',
  };

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
        barangay: _barangay,
      );

      if (!mounted) return;

      setState(() {
        _report = result;
        for (final row in result['barangays'] as List) {
          final name = row['barangay']?.toString().trim();
          if (name != null && name.isNotEmpty) _barangayOptions.add(name);
        }
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
      _barangay = '';
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
    return AidTrackSectionCard(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
                      color: const Color(0xFFE9F5EC),
                      borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 16),
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

  String _appliedFilterSummary() {
    final report = _report;
    if (report == null) return 'Showing: No report loaded';

    String display(dynamic value, String fallback) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? fallback : text;
    }

    final from = display(report['from_date'], '');
    final to = display(report['to_date'], '');
    final barangay = display(report['barangay_filter'], 'All barangays');
    var dates = 'All dates';
    if (from.isNotEmpty && to.isNotEmpty) {
      dates = '$from to $to';
    } else if (from.isNotEmpty) {
      dates = 'From $from';
    } else if (to.isNotEmpty) {
      dates = 'Through $to';
    }
    return 'Registration dates: $dates   |   Barangay: $barangay';
  }

  Widget _filterSection(VoidCallback? downloadPdf) {
    return _section(
      title: 'Report Filters',
      subtitle:
          'Dates filter household registration dates '
          '(Philippine time).',
      icon: Icons.filter_alt_outlined,
      trailing: _refreshButton(),
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
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(_barangay),
                      initialValue: _barangay,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Barangay'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('All barangays')),
                        for (final name in _barangayOptions)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: _isLoading ? null : (value) {
                        setState(() => _barangay = value ?? '');
                      },
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
                  OutlinedButton.icon(
                    onPressed: downloadPdf,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download report (PDF)'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    child: Text(
                      _appliedFilterSummary(),
                      style: const TextStyle(
                        color: AppColors.greyText,
                        fontSize: 12,
                      ),
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
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E2D8), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F5EC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryGreen, size: 23),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: const TextStyle(fontSize: 26,
                    fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                Text(label, style: const TextStyle(color: AppColors.greyText, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _analysis(Map<String, dynamic> totals) {
    final households = _count(totals['total_households']);
    final assessed = _count(totals['assessed_households']);
    final classified = _count(totals['classified_households']);
    if (households == 0) return 'No households match the applied filters.';
    final pending = households - assessed;
    final percent = (100 * assessed / households).toStringAsFixed(0);
    final remaining = switch (pending) {
      0 => 'Every registered household has an assessment.',
      1 => 'One household is awaiting assessment.',
      _ => '$pending households are awaiting assessment.',
    };
    return '$assessed of $households registered households have an assessment ($percent%). '
        '$remaining\n$classified of $assessed assessed households have a classification.';
  }

  Future<void> _export(bool png, Map<String, dynamic> totals,
      List<Map<String, dynamic>> barangays) async {
    if (_exporting || _isLoading || _report == null) return;
    final scope = _appliedFilterSummary();
    setState(() => _exporting = true);
    try {
      late final Uint8List bytes;
      if (png) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        final boundary = _chartKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) throw StateError('Chart is unavailable');
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('PNG encoding failed');
          bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        } finally {
          image.dispose();
        }
      } else {
        bytes = await buildReportPdf(
          totals: totals, barangays: barangays, scope: scope,
          analysis: _analysis(totals), columns: columns,
        );
      }
      if (!mounted) return;
      final extension = png ? 'png' : 'pdf';
      final name = png ? 'aidtrack-assessment-coverage' : 'aidtrack-report';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save AidTrack report',
        fileName: '$name-${_date(DateTime.now())}.$extension',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    } catch (error) {
      debugPrint('Report export failed: $error');
      if (mounted) {
        await _showFeedback(success: false, title: 'Export failed',
            message: 'The file could not be saved. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _analysisCard(Map<String, dynamic> totals, List<Map<String, dynamic>> rows) {
    final households = _count(totals['total_households']);
    final assessed = _count(totals['assessed_households']);
    final ratio = households == 0 ? 0.0 : assessed / households;
    const green = AppColors.primaryGreen;
    const sage = Color(0xffb8dbb6);
    final chart = SizedBox.square(
      dimension: 124,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(child: Padding(
          padding: const EdgeInsets.all(9),
          child: CircularProgressIndicator(
            value: ratio, strokeWidth: 15, color: green,
            backgroundColor: households == 0 ? Colors.grey.shade200 : sage,
            semanticsLabel: 'Assessment coverage',
          ),
        )),
        Text(households == 0 ? '—' : '${(ratio * 100).round()}%',
            style: const TextStyle(color: green, fontSize: 25, fontWeight: FontWeight.bold)),
      ]),
    );
    Widget legend(Color color, String label, int value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: color, size: 12),
        const SizedBox(width: 6),
        Text('$label  $value'),
      ],
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Assessment coverage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Text(_analysis(totals)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          legend(green, 'Assessed', assessed),
          legend(sage, 'Awaiting assessment', households - assessed),
        ]),
      ],
    );
    return _section(
      title: 'Report Analysis',
      subtitle: 'Household assessment coverage',
      icon: Icons.bar_chart_outlined,
      trailing: OutlinedButton.icon(
        onPressed: _exporting || _isLoading ? null : () => _export(true, totals, rows),
        icon: const Icon(Icons.image_outlined),
        label: const Text('Export chart (PNG)'),
      ),
      child: RepaintBoundary(
        key: _chartKey,
        child: Container(
          color: Colors.white, width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AidTrack · Assessment coverage',
                style: TextStyle(color: green, fontWeight: FontWeight.bold)),
            Text(_appliedFilterSummary()),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (_, constraints) {
              if (constraints.maxWidth < 480) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Center(child: chart), const SizedBox(height: 16), description]);
              }
              return Row(children: [chart, const SizedBox(width: 28), Expanded(child: description)]);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _totalsSection(Map<String, dynamic> totals) {
    const fields = <(String, String, IconData)>[
      ('Households', 'total_households', Icons.home_outlined),
      ('Population', 'total_population', Icons.people_outline),
      ('Assessed', 'assessed_households', Icons.assignment_outlined),
      ('Classified', 'classified_households', Icons.analytics_outlined),
    ];

    return _section(
      title: 'Household Overview',
      subtitle: 'Households registered within the selected filters.',
      icon: Icons.home_work_outlined,
      child: _reportMetricGrid(fields, totals),
    );
  }

  Widget _reportMetricGrid(
    List<(String, String, IconData)> fields,
    Map<String, dynamic> totals,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 4
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        final usedColumns = columns > fields.length ? fields.length : columns;
        final cardWidth =
            (constraints.maxWidth - (usedColumns - 1) * 12) / usedColumns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in fields)
              _metricCard(item.$1, _count(totals[item.$2]), item.$3, cardWidth),
          ],
        );
      },
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



    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(AppColors.lightGreen),
        headingTextStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryGreen,
        ),
        dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.darkText),
        horizontalMargin: 12,
        columnSpacing: 22,
        headingRowHeight: 48,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 52,
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
        if (widget.showHeading) ...[
          _section(
            title: widget.heading,
            subtitle: 'Household vulnerability and aid distribution overview',
            icon: Icons.assessment_outlined,
                        child: const SizedBox.shrink(),
          ),
          const SizedBox(height: 18),
        ],

        // Filters and report results use the existing FastAPI data.
        _filterSection(
          report == null || _exporting || _isLoading
              ? null
              : () => _export(false, totals, barangays),
        ),
        const SizedBox(height: 18),

        if (_loadError != null) ...[
          Text(_loadError!, style: const TextStyle(color: Color(0xFFC62828))),
          const SizedBox(height: 12),
        ],

        // ======================================
        // LOADING / EMPTY / RESULTS
        // ======================================
        if (_isLoading && report == null)
          const AidTrackModuleLoading()
        else if (report != null) ...[
          _totalsSection(totals),
          const SizedBox(height: 18),
          _analysisCard(totals, barangays),
          const SizedBox(height: 18),
          _section(
            title: 'Aid Distribution',
            subtitle: 'Distribution records for the households in this report.',
            icon: Icons.inventory_2_outlined,
            child: _reportMetricGrid(const [
              ('Actual deliveries', 'aid_distributions', Icons.local_shipping_outlined),
              ('Practice entries', 'simulated_distributions', Icons.assignment_outlined),
            ], totals),
          ),
          const SizedBox(height: 18),
          _section(
            title: 'Barangay Breakdown',
            subtitle:
                'Household statistics grouped by barangay. '
                'Scroll horizontally to see all columns.',
            icon: Icons.location_city_outlined,
            child: _barangayTable(barangays),
          ),
        ] else if (!_isLoading)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Center(child: Text('No report is available yet.')),
          ),

        const SizedBox(height: 14),
        const Text(
          'Dates filter by household registration date (Philippine time). '
          'Classifications and beneficiary statuses reflect current records. '
          'Verified deliveries exclude practice entries.',
          style: TextStyle(fontSize: 11, color: AppColors.greyText),
        ),
        const SizedBox(height: 18),
      ],
    );
  }
}
