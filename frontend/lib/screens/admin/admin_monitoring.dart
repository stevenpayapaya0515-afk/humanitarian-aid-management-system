import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/aidtrack_section_card.dart';

/// Admin oversight uses GET endpoints only. Staff retains all write actions.
enum AdminMonitoringSection {
  assessments,
  vulnerability,
  beneficiaries,
  distributions,
}

class AdminMonitoringScreen extends StatefulWidget {
  const AdminMonitoringScreen({super.key, required this.section});

  final AdminMonitoringSection section;

  @override
  State<AdminMonitoringScreen> createState() => _AdminMonitoringScreenState();
}

class _AdminMonitoringScreenState extends State<AdminMonitoringScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _candidates = [];
  bool _showCandidates = false;
  Map<String, String> _householdNames = {};
  bool _loading = true;
  String? _error;
  int _requestNumber = 0;
  int _visibleCount = 30;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminMonitoringScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _searchController.clear();
      _query = '';
      _showCandidates = false;
      _visibleCount = 30;
      _load();
    }
  }

  @override
  void dispose() {
    _requestNumber++;
    _searchController.dispose();
    super.dispose();
  }

  String get _path {
    switch (widget.section) {
      case AdminMonitoringSection.assessments:
        return '/assessments';
      case AdminMonitoringSection.vulnerability:
        return '/vulnerability';
      case AdminMonitoringSection.beneficiaries:
        return '/beneficiaries';
      case AdminMonitoringSection.distributions:
        return '/distributions';
    }
  }

  String get _recordName {
    switch (widget.section) {
      case AdminMonitoringSection.assessments:
        return 'Household assessments';
      case AdminMonitoringSection.vulnerability:
        return 'Saved vulnerability classifications';
      case AdminMonitoringSection.beneficiaries:
        return _showCandidates ? 'Beneficiary candidates' : 'Beneficiary records';
      case AdminMonitoringSection.distributions:
        return 'Aid distributions';
    }
  }

  String get _hint {
    switch (widget.section) {
      case AdminMonitoringSection.assessments:
        return 'Search household, barangay, assessment ID...';
      case AdminMonitoringSection.vulnerability:
        return 'Search household, vulnerability level, model version...';
      case AdminMonitoringSection.beneficiaries:
        return 'Search household, beneficiary status, barangay...';
      case AdminMonitoringSection.distributions:
        return 'Search household, aid type, batch code...';
    }
  }

  Future<List<Map<String, dynamic>>> _getRows(String path) async {
    final token = AuthService.accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthException('Please sign in again.');
    }

    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}$path'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      throw const AuthException('Session expired. Please sign in again.');
    }
    if (response.statusCode == 403) {
      throw const AuthException('Administrator read access was denied.');
    }
    if (response.statusCode != 200) {
      throw AuthException('Unable to load records (HTTP ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Expected a list of records.');
    }
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _load() async {
    final requestNumber = ++_requestNumber;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final records = await _getRows(_path);
      final candidates = widget.section == AdminMonitoringSection.beneficiaries
          ? await _getRows('/beneficiaries/candidates')
          : <Map<String, dynamic>>[];
      final names = <String, String>{};
      if (widget.section == AdminMonitoringSection.vulnerability) {
        // Classification responses contain household IDs, not names.
        // Names are loaded through the existing Admin-authorized GET route.
        final households = await _getRows('/households');
        for (final item in households) {
          names['${item['household_id']}'] = _text(item['household_head']);
        }
      }
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _rows = records;
        _candidates = candidates;
        _householdNames = names;
        _visibleCount = 30;
      });
    } on AuthException catch (error) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() => _error = error.message);
    } on TimeoutException {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() => _error = 'Loading timed out. Try Refresh.');
    } on http.ClientException {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() => _error = 'Cannot connect to the FastAPI backend.');
    } catch (_) {
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() => _error = 'Could not read the records. Try Refresh.');
    } finally {
      if (mounted && requestNumber == _requestNumber) {
        setState(() => _loading = false);
      }
    }
  }

  String _text(dynamic value, [String fallback = '—']) {
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString();
  }

  String _nameFor(Map<String, dynamic> row) {
    final direct = row['household_head'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return _text(direct);
    }
    return _householdNames['${row['household_id']}'] ??
        'Household #${_text(row['household_id'])}';
  }

  String _primaryText(Map<String, dynamic> row) {
    switch (widget.section) {
      case AdminMonitoringSection.assessments:
      case AdminMonitoringSection.vulnerability:
      case AdminMonitoringSection.beneficiaries:
        return _nameFor(row);
      case AdminMonitoringSection.distributions:
        return _nameFor(row);
    }
  }

  String _subtitle(Map<String, dynamic> row) {
    switch (widget.section) {
      case AdminMonitoringSection.assessments:
        return 'Assessment #${_text(row['assessment_id'])}  •  '
            '${_text(row['barangay'])}  •  ${_text(row['assessment_date'])}';
      case AdminMonitoringSection.vulnerability:
        return 'Household #${_text(row['household_id'])}  •  '
            'Assessment #${_text(row['assessment_id'])}  •  '
            '${_text(row['created_at'])}';
      case AdminMonitoringSection.beneficiaries:
        if (_showCandidates) {
          return 'Assessment #${_text(row['assessment_id'])}  •  '
              '${_text(row['barangay'])}  •  '
              'Household #${_text(row['household_id'])}';
        }
        return 'Beneficiary #${_text(row['beneficiary_id'])}  •  '
            '${_text(row['barangay'])}  •  '
            'Household #${_text(row['household_id'])}';
      case AdminMonitoringSection.distributions:
        return '${_text(row['aid_type'])}  •  '
            '${_text(row['distribution_date'])}  •  '
            'Batch ${_text(row['batch_code'])}';
    }
  }

  String _status(Map<String, dynamic> row) {
    switch (widget.section) {
      case AdminMonitoringSection.assessments:
        return row['has_classification'] == true ? 'Classified' : 'Unclassified';
      case AdminMonitoringSection.vulnerability:
        return _text(row['predicted_class']);
      case AdminMonitoringSection.beneficiaries:
        return _showCandidates ? 'Candidate' : _text(row['status']);
      case AdminMonitoringSection.distributions:
        return _text(row['beneficiary_status'], 'Recorded');
    }
  }

  Color _statusColor(String value) {
    switch (value.toLowerCase()) {
      case 'high':
      case 'rejected':
        return const Color(0xFFB42318);
      case 'medium':
      case 'for review':
      case 'pending':
      case 'unclassified':
        return const Color(0xFF9A6700);
      default:
        return AppColors.primaryGreen;
    }
  }

  List<Map<String, dynamic>> get _activeRows =>
      widget.section == AdminMonitoringSection.beneficiaries && _showCandidates
          ? _candidates
          : _rows;

  List<Map<String, dynamic>> get _filteredRows {
    final active = _activeRows;
    if (_query.isEmpty) return active;
    return active.where((row) {
      final searchText = [
        _nameFor(row),
        ...row.values.map((value) => value.toString()),
      ].join(' ').toLowerCase();
      return searchText.contains(_query);
    }).toList();
  }

  String _label(String key) {
    if (key == 'data_origin' || key == 'assessment_data_origin') {
      return 'Assessment Data';
    }
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _detailValue(dynamic value, {String? fieldKey}) {
    if (fieldKey == 'data_origin' || fieldKey == 'assessment_data_origin') {
      final source = value?.toString().trim().toLowerCase();
      if (source == 'synthetic') return 'Practice Record';
      if (source == 'lgu_authorized') {
        return 'Verified LGU Household Assessment';
      }
    }
    if (value == null) return 'Not recorded';
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    if (value is bool) return value ? 'Yes' : 'No';
    return _text(value);
  }

  void _showDetails(Map<String, dynamic> record) {
    // Use an explicitly sized Dialog so its list is never measured intrinsically.
    // All four Admin monitoring sections share this read-only detail viewer.
    final fields = record.entries.toList(growable: false);
    final recordTitle = _primaryText(record);
    final isVulnerability =
        widget.section == AdminMonitoringSection.vulnerability;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final dialogWidth =
            (viewport.width - 32.0).clamp(240.0, 720.0).toDouble();
        final dialogHeight =
            (viewport.height - 64.0).clamp(240.0, 650.0).toDouble();

        return Dialog(
          backgroundColor: AppColors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        color: AppColors.primaryGreen,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          recordTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close details',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    'Monitoring view only • Record values are shown as saved.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.greyText,
                    ),
                  ),
                ),
                if (isVulnerability)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      'Model scores are research proxy scores, not verified '
                      'household need or aid eligibility.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.greyText,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    itemCount: fields.length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final field = fields[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _label(field.key),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: AppColors.greyText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _detailValue(field.value, fieldKey: field.key),
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.darkText,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryTile(String name, String value, IconData icon) {
    return SizedBox(
      width: 190,
      child: AidTrackSectionCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: AppColors.primaryGreen, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      )),
                  Text(name,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.greyText,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _summaries() {
    final source = _activeRows;
    final result = <Widget>[
      _summaryTile('Total records', '${source.length}', Icons.list_alt_outlined),
    ];
    void addCount(String label, bool Function(Map<String, dynamic>) condition,
        IconData icon) {
      result.add(_summaryTile(
        label, '${source.where(condition).length}', icon));
    }

    switch (widget.section) {
      case AdminMonitoringSection.assessments:
        addCount('Classified', (row) => row['has_classification'] == true,
            Icons.verified_outlined);
        addCount('Not classified', (row) => row['has_classification'] != true,
            Icons.pending_actions_outlined);
        break;
      case AdminMonitoringSection.vulnerability:
        for (final level in ['Low', 'Medium', 'High']) {
          addCount(level, (row) => row['predicted_class'] == level,
              Icons.analytics_outlined);
        }
        break;
      case AdminMonitoringSection.beneficiaries:
        if (_showCandidates) {
          result.add(_summaryTile('Registered records', '${_rows.length}',
              Icons.people_outline));
        } else {
          result.add(_summaryTile('Candidates', '${_candidates.length}',
              Icons.person_search_outlined));
          for (final status in ['Pending', 'For Review', 'Approved', 'Rejected']) {
            addCount(status, (row) => row['status'] == status,
                Icons.people_outline);
          }
        }
        break;
      case AdminMonitoringSection.distributions:
        final distinctTypes = source
            .map((row) => row['aid_type'])
            .whereType<String>()
            .toSet()
            .length;
        result.add(_summaryTile(
          'Aid types', '$distinctTypes', Icons.inventory_2_outlined));
        addCount('Financial grants',
            (row) => row['amount_php'] != null, Icons.payments_outlined);
        break;
    }
    return result;
  }

  Widget _recordCard(Map<String, dynamic> row) {
    final status = _status(row);
    final statusColor = _statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AidTrackSectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: LayoutBuilder(builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 540;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_primaryText(row),
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  )),
              const SizedBox(height: 4),
              Text(_subtitle(row),
                  style: const TextStyle(
                    color: AppColors.greyText,
                    fontSize: 12,
                  )),
            ],
          );
          final statusTag = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
          );
          final detailButton = OutlinedButton.icon(
            onPressed: () => _showDetails(row),
            icon: const Icon(Icons.visibility_outlined, size: 17),
            label: const Text('View details'),
          );
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [statusTag, detailButton],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 10),
              statusTag,
              const SizedBox(width: 12),
              detailButton,
            ],
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRows;
    final visible = filtered.take(_visibleCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AidTrackSectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.visibility_outlined,
                  color: AppColors.primaryGreen),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Administrator monitoring only. Record creation, editing, '
                  'classification and distribution actions belong to LGU Staff.',
                  style: TextStyle(color: AppColors.darkText, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Refresh records',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: AppColors.primaryGreen),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!_loading && _error == null) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final mobile = MediaQuery.sizeOf(context).width < 900;
              final width = constraints.maxWidth;
              final columns = width >= 310 ? 2 : 1;
              final tileWidth = mobile ? (width - gap * (columns - 1)) / columns : 190.0;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final tile in _summaries())
                    SizedBox(width: tileWidth, child: tile),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
        ],
        AidTrackSectionCard(
          title: _recordName,
          subtitle: widget.section == AdminMonitoringSection.vulnerability
              ? 'Saved history: a household may have more than one classification.'
              : 'View records and details without modifying household data.',
          icon: Icons.manage_search_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.section == AdminMonitoringSection.beneficiaries) ...[
                Wrap(spacing: 10, runSpacing: 8, children: [
                  ChoiceChip(
                    label: const Text('Registered beneficiaries'),
                    selected: !_showCandidates,
                    onSelected: (_) => setState(() {
                      _showCandidates = false;
                      _visibleCount = 30;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Candidates for review'),
                    selected: _showCandidates,
                    onSelected: (_) => setState(() {
                      _showCandidates = true;
                      _visibleCount = 30;
                    }),
                  ),
                ]),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                  _visibleCount = 30;
                }),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _hint,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = '';
                              _visibleCount = 30;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                Column(
                  children: [
                    Text(_error!,
                        style: const TextStyle(color: Color(0xFFB42318))),
                    TextButton(onPressed: _load, child: const Text('Try again')),
                  ],
                )
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No matching records found.')),
                )
              else ...[
                Text('Showing ${visible.length} of ${filtered.length} records',
                    style: const TextStyle(
                        color: AppColors.greyText, fontSize: 12)),
                const SizedBox(height: 12),
                for (final record in visible) _recordCard(record),
                if (visible.length < filtered.length)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _visibleCount += 30),
                      child: const Text('Load more records'),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (widget.section == AdminMonitoringSection.vulnerability) ...[
          const SizedBox(height: 12),
          const Text(
            'These are saved preliminary research-proxy classifications. '
            'LGU Staff must review results before beneficiary decisions.',
            style: TextStyle(fontSize: 12, color: AppColors.greyText),
          ),
        ],
      ],
    );
  }
}
