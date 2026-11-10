import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/distribution_service.dart';

class AidDistributionScreen extends StatefulWidget {
  const AidDistributionScreen({super.key});

  @override
  State<AidDistributionScreen> createState() => _AidDistributionScreenState();
}

class _AidDistributionScreenState extends State<AidDistributionScreen> {
  final _formKey = GlobalKey<FormState>();

  final _beneficiaryController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _batchController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  static const _aidTypes = [
    'Food Packs',
    'Drinking Water',
    'Hygiene Kits',
    'Clothing',
    'Blankets',
    'Medical Supplies',
    'Other',
  ];

  static const _units = [
    'packs',
    'pieces',
    'liters',
    'kilograms',
    'boxes',
    'sets',
  ];

  List<Map<String, dynamic>> _beneficiaries = [];
  List<Map<String, dynamic>> _distributions = [];

  int? _selectedBeneficiaryId;
  String _selectedAidType = 'Food Packs';
  String _selectedUnit = 'packs';
  DateTime _selectedDate = DateTime.now();

  bool _isLoadingBeneficiaries = true;
  bool _isLoadingRecords = true;
  bool _isSaving = false;

  String? _beneficiaryError;
  String? _recordsError;
  String? _saveError;
  String? _selectionError;

  @override
  void initState() {
    super.initState();
    _beneficiaryController.addListener(_checkBeneficiarySelection);
    _loadBeneficiaries();
    _loadDistributions();
  }

  @override
  void dispose() {
    _beneficiaryController.removeListener(_checkBeneficiarySelection);
    _beneficiaryController.dispose();
    _quantityController.dispose();
    _batchController.dispose();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ==========================================
  // HELPERS
  // ==========================================

  int _id(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String _text(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return '—';
    }
    return value.toString();
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
      return 'Unexpected server response.';
    }

    return 'Unable to complete the request. Check the backend.';
  }

  String _isoDate(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'Date unavailable';

    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();

    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _beneficiaryLabel(Map<String, dynamic> item) {
    return 'B-${_id(item['beneficiary_id'])} | '
        '${_text(item['household_head'])} | '
        '${_text(item['barangay'])}';
  }

  void _checkBeneficiarySelection() {
    final id = _selectedBeneficiaryId;
    if (id == null) return;

    for (final item in _beneficiaries) {
      if (_id(item['beneficiary_id']) == id) {
        if (_beneficiaryController.text != _beneficiaryLabel(item)) {
          setState(() => _selectedBeneficiaryId = null);
        }
        return;
      }
    }

    setState(() => _selectedBeneficiaryId = null);
  }

  Color _classColor(String value) {
    switch (value) {
      case 'High':
        return const Color(0xFFC62828);
      case 'Medium':
        return const Color(0xFFAB7800);
      case 'Low':
        return AppColors.primaryGreen;
      default:
        return AppColors.greyText;
    }
  }

  // ==========================================
  // SUCCESS AND ERROR MODAL
  // ==========================================

  Future<void> _showFeedbackDialog({
    required bool success,
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle_outline : Icons.error_outline,
              color: success ? AppColors.primaryGreen : const Color(0xFFC62828),
              size: 58,
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
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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

  void _showSavingDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                  strokeWidth: 3,
                ),

                SizedBox(height: 20),

                Text(
                  'Saving Simulation...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),

                SizedBox(height: 8),

                Text(
                  'Please wait while the distribution record is saved.',
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

  String _defaultUnit(String aidType) {
    switch (aidType) {
      case 'Drinking Water':
        return 'liters';
      case 'Clothing':
      case 'Blankets':
        return 'pieces';
      case 'Hygiene Kits':
        return 'sets';
      case 'Medical Supplies':
        return 'boxes';
      default:
        return 'packs';
    }
  }

  // ==========================================
  // FETCH BACKEND RECORDS
  // ==========================================

  Future<void> _loadBeneficiaries() async {
    if (_isLoadingBeneficiaries && _beneficiaries.isNotEmpty) return;

    setState(() {
      _isLoadingBeneficiaries = true;
      _beneficiaryError = null;
    });

    try {
      final records = await DistributionService.fetchBeneficiaries();

      if (!mounted) return;

      setState(() => _beneficiaries = records);
    } catch (error) {
      if (!mounted) return;

      setState(() => _beneficiaryError = _errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _isLoadingBeneficiaries = false);
      }
    }
  }

  Future<void> _loadDistributions() async {
    setState(() {
      _isLoadingRecords = true;
      _recordsError = null;
    });

    try {
      final records = await DistributionService.fetchDistributions();

      if (!mounted) return;

      setState(() => _distributions = records);
    } catch (error) {
      if (!mounted) return;

      setState(() => _recordsError = _errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecords = false);
      }
    }
  }

  // ==========================================
  // SELECT DISTRIBUTION DATE
  // ==========================================

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final initial = _selectedDate.isAfter(today) ? today : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: today,
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  // ==========================================
  // SAVE DISTRIBUTION SIMULATION
  // ==========================================

  Future<void> _saveDistribution() async {
    if (_isSaving || _isLoadingBeneficiaries) return;

    FocusScope.of(context).unfocus();

    final selectedId = _selectedBeneficiaryId;

    setState(() {
      _saveError = null;
      _selectionError = null;
    });

    // ========================================
    // VALIDATE BENEFICIARY SELECTION
    // ========================================

    if (selectedId == null) {
      const message = 'Please select a beneficiary record.';

      setState(() {
        _selectionError = message;
      });

      await _showFeedbackDialog(
        success: false,
        title: 'Incomplete Distribution Form',
        message: message,
      );

      return;
    }

    // ========================================
    // VALIDATE REQUIRED FIELDS
    // ========================================

    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showFeedbackDialog(
        success: false,
        title: 'Invalid Distribution Information',
        message:
            'Please complete the required fields and correct '
            'the highlighted errors before saving.',
      );

      return;
    }

    // ========================================
    // BEGIN LOADING STATE
    // ========================================

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    // Display a non-dismissible loading modal.
    _showSavingDialog();

    bool savedSuccessfully = false;
    String? failureMessage;

    try {
      // ======================================
      // SEND RECORD TO FASTAPI
      // ======================================

      await DistributionService.createDistribution(
        beneficiaryId: selectedId,
        aidType: _selectedAidType,
        quantity: int.parse(_quantityController.text.trim()),
        unit: _selectedUnit,
        distributionDate: _isoDate(_selectedDate),
        batchCode: _batchController.text.trim().toUpperCase(),
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;

      savedSuccessfully = true;
    } catch (error) {
      failureMessage = _errorMessage(error);
    } finally {
      if (mounted) {
        // Close the loading modal after the API finishes.
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _isSaving = false;
          _saveError = failureMessage;
        });
      }
    }

    if (!mounted) return;

    // ========================================
    // ERROR RESPONSE
    // ========================================

    if (!savedSuccessfully) {
      await _showFeedbackDialog(
        success: false,
        title: 'Distribution Not Saved',
        message: failureMessage ?? 'An unexpected error occurred while saving.',
      );

      return;
    }

    // ========================================
    // SUCCESS RESPONSE
    // ========================================

    // Reset only after FastAPI confirms a successful save.
    _formKey.currentState?.reset();

    _beneficiaryController.clear();
    _quantityController.text = '1';
    _batchController.clear();
    _notesController.clear();

    setState(() {
      _selectedBeneficiaryId = null;
      _selectedAidType = 'Food Packs';
      _selectedUnit = 'packs';
      _selectedDate = DateTime.now();

      _selectionError = null;
      _saveError = null;
    });

    // Reload distribution history from PostgreSQL.
    await _loadDistributions();

    if (!mounted) return;

    // Show the result in a modal instead of a SnackBar.
    await _showFeedbackDialog(
      success: true,
      title: 'Distribution Simulation Saved',
      message: _recordsError == null
          ? 'The aid distribution simulation has been '
                'successfully saved to the database.'
          : 'The simulation was saved, but the records could '
                'not be refreshed. Please use Refresh records '
                'to reload the list.',
    );
  }

  // ==========================================
  // REUSABLE REFRESH BUTTON
  // ==========================================

  Widget _refreshButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: loading || _isSaving ? null : onPressed,
        borderRadius: BorderRadius.circular(24),

        // Grey appears only when the cursor hovers.
        hoverColor: const Color(0xFFE5E7EB),
        splashColor: AppColors.lightGreen,
        highlightColor: AppColors.lightGreen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
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
                loading ? 'Refreshing...' : label,
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
  // REUSABLE SECTION CARD
  // ==========================================

  Widget _sectionCard({
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
                    child: Icon(icon, size: 22, color: AppColors.primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.darkText,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.greyText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!mobile && trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing,
                  ],
                ],
              ),
              if (mobile && trailing != null) ...[
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],
              const SizedBox(height: 20),
              child,
            ],
          );
        },
      ),
    );
  }

  Widget _errorBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFFB71C1C))),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ==========================================
  // SIMULATION REGISTRATION FORM
  // ==========================================

  Widget _buildDistributionForm() {
    return _sectionCard(
      title: 'Record Aid Distribution Simulation',
      subtitle: 'Enter assistance details for a beneficiary review record.',
      icon: Icons.inventory_2_outlined,
      trailing: _refreshButton(
        label: 'Refresh beneficiaries',
        loading: _isLoadingBeneficiaries,
        onPressed: _loadBeneficiaries,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_beneficiaryError != null) ...[
              _errorBox(_beneficiaryError!),
              const SizedBox(height: 12),
            ],

            if (_isLoadingBeneficiaries)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),

            if (!_isLoadingBeneficiaries && _beneficiaries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'No beneficiary review records available. '
                  'Register a household in Beneficiary Management first.',
                  style: TextStyle(color: AppColors.greyText),
                ),
              ),

            LayoutBuilder(
              builder: (context, constraints) {
                return DropdownMenu<int>(
                  width: constraints.maxWidth,
                  menuHeight: 300,
                  controller: _beneficiaryController,
                  enabled:
                      !_isSaving &&
                      !_isLoadingBeneficiaries &&
                      _beneficiaries.isNotEmpty,
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,
                  label: const Text('Select Beneficiary Record'),
                  hintText: 'Search by beneficiary ID, name, or barangay',
                  leadingIcon: const Icon(Icons.people_outline),
                  dropdownMenuEntries: _beneficiaries.map((item) {
                    return DropdownMenuEntry<int>(
                      value: _id(item['beneficiary_id']),
                      label: _beneficiaryLabel(item),
                    );
                  }).toList(),
                  onSelected: (value) {
                    setState(() {
                      _selectedBeneficiaryId = value;
                      _selectionError = null;
                    });
                  },
                );
              },
            ),

            if (_selectionError != null) ...[
              const SizedBox(height: 6),
              Text(
                _selectionError!,
                style: const TextStyle(color: Color(0xFFC62828), fontSize: 12),
              ),
            ],

            const SizedBox(height: 18),

            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final width = compact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 32) / 3;

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedAidType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Aid Type',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: _aidTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type),
                          );
                        }).toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _selectedAidType = value;
                                  _selectedUnit = _defaultUnit(value);
                                });
                              },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        controller: _quantityController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                        validator: (value) {
                          final number = int.tryParse(value?.trim() ?? '');

                          if (number == null || number < 1 || number > 100000) {
                            return 'Enter a quantity from 1 to 100000.';
                          }

                          return null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_selectedAidType),
                        initialValue: _selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          prefixIcon: Icon(Icons.straighten_outlined),
                        ),
                        items: _units.map((unit) {
                          return DropdownMenuItem(
                            value: unit,
                            child: Text(unit),
                          );
                        }).toList(),
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _selectedUnit = value);
                                }
                              },
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 16),

            InkWell(
              onTap: _isSaving ? null : _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Distribution Date',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(_isoDate(_selectedDate))),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _batchController,
              enabled: !_isSaving,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Distribution Batch Code',
                hintText: 'Example: DEMO-20261110-B',
                prefixIcon: Icon(Icons.tag_outlined),
                counterText: '',
              ),
              validator: (value) {
                final code = value?.trim() ?? '';

                if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{2,31}$')
                    .hasMatch(code)) {
                  return 'Use 3–32 letters, numbers, - or _.';
                }

                return null;
              },
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _notesController,
              enabled: !_isSaving,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Simulation Notes (optional)',
                alignLabelWithHint: true,
                hintText: 'No physical assistance was released.',
              ),
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
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
                      'Simulation only. This record does not '
                      'represent actual humanitarian aid delivery. '
                      'Pending and For Review beneficiaries are used '
                      'only for testing.',
                      style: TextStyle(color: AppColors.darkText, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

            if (_saveError != null) ...[
              const SizedBox(height: 12),
              _errorBox(_saveError!),
            ],

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving || _isLoadingBeneficiaries
                    ? null
                    : _saveDistribution,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _isSaving
                      ? 'Saving Simulation...'
                      : 'Save Distribution Simulation',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.white,
                  minimumSize: const Size(0, 50),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DISTRIBUTION HISTORY
  // ==========================================

  List<Map<String, dynamic>> get _filteredDistributions {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) return _distributions;

    return _distributions.where((record) {
      final searchable = [
        record['distribution_id'],
        record['beneficiary_id'],
        record['household_head'],
        record['barangay'],
        record['aid_type'],
        record['batch_code'],
        record['distribution_date'],
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  Widget _distributionCard(Map<String, dynamic> record) {
    final vulnerability = _text(record['predicted_class']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _text(record['household_head']),
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              _chip('Simulation Only', const Color(0xFF9A6800)),
              _chip('$vulnerability Vulnerability', _classColor(vulnerability)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Distribution #${_text(record['distribution_id'])} '
            '• Beneficiary #${_text(record['beneficiary_id'])}',
          ),
          const SizedBox(height: 5),
          Text('Barangay: ${_text(record['barangay'])}'),
          const SizedBox(height: 5),
          Text('Aid Type: ${_text(record['aid_type'])}'),
          const SizedBox(height: 5),
          Text(
            'Quantity: ${_text(record['quantity'])} '
            '${_text(record['unit'])}',
          ),
          const SizedBox(height: 5),
          Text(
            'Distribution Date: '
            '${_formatDate(record['distribution_date'])}',
          ),
          const SizedBox(height: 5),
          Text('Batch Code: ${_text(record['batch_code'])}'),
          const SizedBox(height: 5),
          Text(
            'Beneficiary Status: '
            '${_text(record['beneficiary_status'])}',
          ),
          const SizedBox(height: 5),
          Text('Notes: ${_text(record['notes'])}'),
        ],
      ),
    );
  }

  Widget _buildDistributionHistory() {
    final records = _filteredDistributions;

    return _sectionCard(
      title: 'Aid Distribution Records',
      subtitle: 'Saved humanitarian aid distribution simulations.',
      icon: Icons.history_outlined,
      trailing: _refreshButton(
        label: 'Refresh records',
        loading: _isLoadingRecords,
        onPressed: _loadDistributions,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search household, aid type, batch, or ID...',
              prefixIcon: Icon(Icons.search),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            '${records.length} distribution records',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),

          const SizedBox(height: 14),

          if (_recordsError != null) ...[
            _errorBox(_recordsError!),
            const SizedBox(height: 12),
          ],

          if (_isLoadingRecords)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primaryGreen),
              ),
            )
          else if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No distribution records found.',
                  style: TextStyle(color: AppColors.greyText),
                ),
              ),
            )
          else
            ...records.map(_distributionCard),
        ],
      ),
    );
  }

  // ==========================================
  // MAIN SCREEN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Aid Distribution',
          style: TextStyle(
            color: AppColors.darkText,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Record and monitor humanitarian assistance simulations.',
          style: TextStyle(color: AppColors.greyText, fontSize: 13),
        ),

        const SizedBox(height: 20),

        _buildDistributionForm(),

        const SizedBox(height: 22),

        _buildDistributionHistory(),
      ],
    );
  }
}
