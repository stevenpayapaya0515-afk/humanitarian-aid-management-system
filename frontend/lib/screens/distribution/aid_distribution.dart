import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/distribution_service.dart';
import '../../widgets/aidtrack_module_loading.dart';

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
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();
  final _sourceController = TextEditingController();
  final _searchController = TextEditingController();
  final _correctionReasonController = TextEditingController();

  static const _aidTypes = [
    'Food Packs',
    'Drinking Water',
    'Hygiene Kits',
    'Clothing',
    'Blankets',
    'Medical Supplies',
    'School Supplies',
    'Shelter Materials',
    'Livelihood Kits',
    'Medical Assistance',
    'Educational Assistance',
    'Burial Assistance',
    'Transportation Assistance',
    'Cash Relief',
    'Livelihood Assistance',
    'Other',
  ];

  static const _financialAidTypes = <String>{
    'Medical Assistance',
    'Educational Assistance',
    'Burial Assistance',
    'Transportation Assistance',
    'Cash Relief',
    'Livelihood Assistance',
  };

  bool get _isFinancialAid => _financialAidTypes.contains(_selectedAidType);

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

  bool _deliveryConfirmed = false;
  bool _batchCodeEdited = false;
  Map<String, dynamic>? _editingDistribution;
  bool _correctionConfirmed = false;

  Map<String, dynamic>? get _selectedRecord {
    if (_editingDistribution != null) return _editingDistribution;
    for (final item in _beneficiaries) {
      if (_id(item['beneficiary_id']) == _selectedBeneficiaryId) return item;
    }
    return null;
  }

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
    _batchController.text = _suggestBatchCode(_selectedDate);
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
    _amountController.dispose();
    _purposeController.dispose();
    _sourceController.dispose();
    _searchController.dispose();
    _correctionReasonController.dispose();
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
                  'Saving Distribution...',
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
      case 'Livelihood Kits':
        return 'sets';
      case 'Medical Supplies':
      case 'School Supplies':
        return 'boxes';
      case 'Shelter Materials':
        return 'pieces';
      case 'Medical Assistance':
      case 'Educational Assistance':
      case 'Burial Assistance':
      case 'Transportation Assistance':
      case 'Cash Relief':
      case 'Livelihood Assistance':
        return 'grants';
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

      setState(() {
        _distributions = records;
        if (!_batchCodeEdited) {
          _batchController.text = _suggestBatchCode(_selectedDate);
        }
      });
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
      setState(() {
        _selectedDate = picked;
        if (!_batchCodeEdited) {
          _batchController.text = _suggestBatchCode(picked);
        }
      });
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
        quantity: _isFinancialAid
            ? 1
            : int.parse(_quantityController.text.trim()),
        unit: _selectedUnit,
        amountPhp: _isFinancialAid
            ? double.parse(_amountController.text.trim())
            : null,
        assistancePurpose: _purposeController.text.trim(),
        sourceAgency: _sourceController.text.trim(),
        distributionDate: _isoDate(_selectedDate),
        batchCode: _batchController.text.trim().toUpperCase(),
        notes: _notesController.text.trim(),
        expectedAssessmentId: _id(_selectedRecord?['assessment_id']),
        expectedClassificationId: _id(_selectedRecord?['classification_id']),
        deliveryConfirmed: _deliveryConfirmed,
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
    _amountController.clear();
    _purposeController.clear();
    _sourceController.clear();

    setState(() {
      _selectedBeneficiaryId = null;
      _deliveryConfirmed = false;
      _selectedAidType = 'Food Packs';
      _selectedUnit = 'packs';
      _selectedDate = DateTime.now();

      _selectionError = null;
      _saveError = null;
    });

    // Reload distribution history from PostgreSQL.
    // Prepare the next event-code suggestion after a successful save.
    _batchCodeEdited = false;
    await _loadDistributions();
    if (mounted) _useSuggestedBatchCode();

    if (!mounted) return;

    // Show the result in a modal instead of a SnackBar.
    await _showFeedbackDialog(
      success: true,
      title: 'Distribution Record Saved',
      message: _recordsError != null
          ? 'The record was saved, but the list could not refresh. Use Refresh records.'
          : 'The distribution information has been saved successfully.',
    );
  }

  // Edit in the main form, not in a dialog.
  void _editDistribution(Map<String, dynamic> record) {
    if (_isSaving) return;
    _formKey.currentState?.reset();
    _beneficiaryController.clear();
    _quantityController.text = '${record['quantity'] ?? 1}';
    _amountController.text = record['amount_php']?.toString() ?? '';
    _purposeController.text = (record['assistance_purpose'] ?? '').toString();
    _sourceController.text = (record['source_agency'] ?? '').toString();
    _batchController.text = (record['batch_code'] ?? '').toString();
    _notesController.text = (record['notes'] ?? '').toString();
    _correctionReasonController.clear();
    _batchCodeEdited = true;

    final aidType = (record['aid_type'] ?? '').toString();
    final unit = (record['unit'] ?? '').toString();
    setState(() {
      _editingDistribution = Map<String, dynamic>.from(record);
      _selectedBeneficiaryId = _id(record['beneficiary_id']);
      _selectedAidType = _aidTypes.contains(aidType) ? aidType : 'Other';
      _selectedUnit = _financialAidTypes.contains(aidType)
          ? 'grants'
          : (_units.contains(unit) ? unit : _defaultUnit(_selectedAidType));
      _selectedDate =
          DateTime.tryParse('${record['distribution_date']}') ?? DateTime.now();
      _correctionConfirmed = false;
      _deliveryConfirmed = false;
      _saveError = null;
      _selectionError = null;
    });

    // Scroll only after the existing form has switched to editing mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final formContext = _formKey.currentContext;
      if (formContext != null) {
        Scrollable.ensureVisible(
          formContext,
          duration: const Duration(milliseconds: 300),
          alignment: 0,
        );
      }
    });
  }

  Future<void> _updateDistribution() async {
    if (_isSaving) return;
    final record = _editingDistribution;
    if (record == null) return;
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showFeedbackDialog(
        success: false,
        title: 'Invalid Correction',
        message: 'Please correct the highlighted fields before updating.',
      );
      return;
    }
    if (record['is_simulation'] != true && !_correctionConfirmed) {
      setState(() {
        _saveError =
            'Verify the correction against the original delivery record first.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    _showSavingDialog();
    String? failureMessage;
    bool updated = false;

    try {
      await DistributionService.updateDistribution(
        _id(record['distribution_id']),
        {
          'beneficiary_id': _id(record['beneficiary_id']),
          'expected_assessment_id': _id(record['assessment_id']),
          'expected_classification_id': _id(record['classification_id']),
          'expected_revision': _id(record['revision']),
          'delivery_confirmed': _correctionConfirmed,
          'aid_type': _selectedAidType,
          'quantity': _isFinancialAid
              ? 1
              : int.parse(_quantityController.text.trim()),
          'unit': _isFinancialAid ? 'grants' : _selectedUnit,
          'amount_php': _isFinancialAid
              ? double.parse(_amountController.text.trim())
              : null,
          'assistance_purpose': _purposeController.text.trim(),
          'source_agency': _sourceController.text.trim(),
          'distribution_date': _isoDate(_selectedDate),
          'batch_code': _batchController.text.trim().toUpperCase(),
          'notes': _notesController.text.trim(),
          'correction_reason': _correctionReasonController.text.trim(),
        },
      );
      updated = true;
    } catch (error) {
      failureMessage = _errorMessage(error);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _isSaving = false;
          _saveError = failureMessage;
        });
      }
    }
    if (!mounted) return;
    if (!updated) {
      await _showFeedbackDialog(
        success: false,
        title: 'Distribution Not Updated',
        message: failureMessage ?? 'Unable to save the correction.',
      );
      return;
    }

    _clearDistributionForm();
    await _loadDistributions();
    if (!mounted) return;
    await _showFeedbackDialog(
      success: true,
      title: 'Distribution Updated',
      message: _recordsError == null
          ? 'The correction was saved with its reason and Staff audit history.'
          : 'The correction was saved, but records could not refresh. Select Refresh records.',
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
  // CLEAN DISTRIBUTION FORM
  // ==========================================

  // Suggest a new EVENT reference. Staff can reuse an existing batch when
  // several beneficiaries receive assistance under the same event.
  String _suggestBatchCode(DateTime date) {
    final datePart =
        '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    final prefix = 'AID-$datePart-';
    var largest = 0;
    for (final record in _distributions) {
      final code = (record['batch_code'] ?? '').toString().toUpperCase();
      if (!code.startsWith(prefix)) continue;
      final suffix = code.substring(prefix.length);
      if (!RegExp(r'^\d+$').hasMatch(suffix)) continue;
      final number = int.tryParse(suffix);
      if (number != null && number > largest) largest = number;
    }
    return '$prefix${(largest + 1).toString().padLeft(3, '0')}';
  }

  void _useSuggestedBatchCode() {
    _batchCodeEdited = false;
    _batchController.text = _suggestBatchCode(_selectedDate);
  }

  // Cancel clears only unsaved form values; it never changes stored records.
  void _clearDistributionForm() {
    if (_isSaving) return;
    _formKey.currentState?.reset();
    _beneficiaryController.clear();
    _quantityController.text = '1';
    _amountController.clear();
    _purposeController.clear();
    _sourceController.clear();
    _notesController.clear();
    _correctionReasonController.clear();
    final today = DateTime.now();
    _batchCodeEdited = false;
    _batchController.text = _suggestBatchCode(today);
    setState(() {
      _editingDistribution = null;
      _correctionConfirmed = false;
      _selectedBeneficiaryId = null;
      _selectedAidType = 'Food Packs';
      _selectedUnit = 'packs';
      _selectedDate = today;
      _deliveryConfirmed = false;
      _selectionError = null;
      _saveError = null;
    });
  }

  Widget _distributionFormGroup({
    required String title,
    required IconData icon,
    required Widget child,
    String? description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primaryGreen, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(fontSize: 12, color: AppColors.greyText),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _distributionFieldPair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 16), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _buildDistributionForm() {
    return _sectionCard(
      title: _editingDistribution == null
          ? 'Record Aid Distribution'
          : 'Update Aid Distribution',
      subtitle: _editingDistribution == null
          ? 'Record assistance for an approved, reviewed beneficiary.'
          : 'Correct saved transaction details. Every update is recorded in history.',
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
              const SizedBox(height: 16),
            ],
            if (_isLoadingBeneficiaries) const AidTrackModuleLoading(),
            if (!_isLoadingBeneficiaries &&
                _beneficiaries.isEmpty &&
                _editingDistribution == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'No approved beneficiaries with current classifications. '
                  'Complete review in Beneficiary Management first.',
                  style: TextStyle(color: AppColors.greyText),
                ),
              ),

            if (_editingDistribution != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_outlined,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Editing Distribution #${_text(_editingDistribution!['distribution_id'])} '
                        '· ${_text(_editingDistribution!['household_head'])}',
                        style: const TextStyle(
                          color: AppColors.darkText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            _distributionFormGroup(
              title: '1. Beneficiary',
              icon: Icons.people_outline,
              description: _editingDistribution == null
                  ? 'Select a household and verify its assessment reference.'
                  : 'The original beneficiary and assessment reference are protected.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editingDistribution != null)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Beneficiary (locked during correction)',
                        prefixIcon: Icon(Icons.people_outline),
                      ),
                      child: Text(
                        'B-${_text(_editingDistribution!['beneficiary_id'])} | '
                        '${_text(_editingDistribution!['household_head'])} | '
                        '${_text(_editingDistribution!['barangay'])}',
                        style: const TextStyle(color: AppColors.darkText),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) => DropdownMenu<int>(
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
                        hintText: 'Search by beneficiary ID, name or barangay',
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
                            _deliveryConfirmed = false;
                            _selectionError = null;
                          });
                        },
                      ),
                    ),
                  if (_selectionError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _selectionError!,
                      style: const TextStyle(
                        color: Color(0xFFC62828),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_selectedRecord != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.lightGreen,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _text(_selectedRecord!['household_head']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkText,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Household #${_text(_selectedRecord!['household_id'])}  •  '
                            '${_text(_selectedRecord!['household_size'])} members  •  '
                            '${_text(_selectedRecord!['barangay'])}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.darkText,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Assessment #${_text(_selectedRecord!['assessment_id'])}  •  '
                            'Classification #${_text(_selectedRecord!['classification_id'])}  •  '
                            '${_text(_selectedRecord!['predicted_class'])} vulnerability',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.greyText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            _distributionFormGroup(
              title: '2. Assistance Details',
              icon: Icons.volunteer_activism_outlined,
              description:
                  'Specify what is being provided and the assessed need.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('aid-type-$_selectedAidType'),
                    initialValue: _selectedAidType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Aid Type',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: _aidTypes.map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedAidType = value;
                              _selectedUnit = _defaultUnit(value);
                              _amountController.clear();
                            });
                          },
                  ),
                  const SizedBox(height: 16),
                  if (_isFinancialAid)
                    TextFormField(
                      key: const ValueKey('aid-amount'),
                      controller: _amountController,
                      enabled: !_isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Assistance Amount (PHP)',
                        hintText: 'e.g. 1500.00',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        final amount = double.tryParse(text);
                        if (amount == null ||
                            !amount.isFinite ||
                            amount <= 0 ||
                            amount > 9999999999.99 ||
                            !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)) {
                          return 'Enter a valid PHP amount (up to 2 decimal places).';
                        }
                        return null;
                      },
                    )
                  else
                    _distributionFieldPair(
                      TextFormField(
                        key: const ValueKey('aid-quantity'),
                        controller: _quantityController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          prefixIcon: Icon(Icons.numbers_outlined),
                        ),
                        validator: (value) {
                          final quantity = int.tryParse(value?.trim() ?? '');
                          if (quantity == null ||
                              quantity < 1 ||
                              quantity > 100000) {
                            return 'Enter a quantity from 1 to 100000.';
                          }
                          return null;
                        },
                      ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('unit-$_selectedAidType'),
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
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _purposeController,
                    enabled: !_isSaving,
                    maxLength: 250,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Reason / Assessed Need',
                      alignLabelWithHint: true,
                      hintText: 'Explain why this assistance is needed',
                      prefixIcon: Icon(Icons.assignment_outlined),
                    ),
                    validator: (value) {
                      if ((value?.trim().length ?? 0) < 5) {
                        return 'Describe the assessed need (at least 5 characters).';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sourceController,
                    enabled: !_isSaving,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Program / Source (optional)',
                      hintText: 'Enter only a verified program or source',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _distributionFormGroup(
              title: '3. Distribution Reference',
              icon: Icons.event_note_outlined,
              description: 'Set the date and event batch reference.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _distributionFieldPair(
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
                    TextFormField(
                      controller: _batchController,
                      enabled: !_isSaving,
                      maxLength: 32,
                      onChanged: (_) => _batchCodeEdited = true,
                      decoration: InputDecoration(
                        labelText: 'Distribution Batch Code',
                        hintText: 'AID-YYYYMMDD-001',
                        prefixIcon: const Icon(Icons.tag_outlined),
                        counterText: '',
                        suffixIcon: IconButton(
                          tooltip: 'Suggest next batch code',
                          icon: const Icon(Icons.autorenew),
                          onPressed: _isSaving || _editingDistribution != null
                              ? null
                              : _useSuggestedBatchCode,
                        ),
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
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A batch identifies a distribution event. A code is suggested '
                    'automatically; edit or reuse it if the assistance belongs '
                    'to an existing authorized event.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AppColors.greyText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    enabled: !_isSaving,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Additional information or follow-up',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_editingDistribution != null) ...[
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _correctionReasonController,
                      enabled: !_isSaving,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Correction Reason (required)',
                        hintText:
                            'What was incorrect, and why is it being changed?',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.rate_review_outlined),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 10
                          ? 'Explain the correction (at least 10 characters).'
                          : null,
                    ),
                    if (_editingDistribution!['is_simulation'] != true) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _correctionConfirmed,
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(
                                () => _correctionConfirmed = value ?? false,
                              ),
                        title: const Text(
                          'I verified this correction against the actual delivery record.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                  if (_editingDistribution == null &&
                      _selectedRecord != null) ...[
                    if (_selectedRecord!['assessment_data_origin'] !=
                        'synthetic')
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _deliveryConfirmed,
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(
                                () => _deliveryConfirmed = value ?? false,
                              ),
                        title: const Text(
                          'I confirm the recipient received this assistance '
                          'on the recorded date.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_saveError != null) ...[
              const SizedBox(height: 16),
              _errorBox(_saveError!),
            ],
            const SizedBox(height: 22),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cancelButton = OutlinedButton(
                      onPressed: _isSaving ? null : _clearDistributionForm,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryGreen,
                        side: const BorderSide(color: AppColors.primaryGreen),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _editingDistribution == null
                            ? 'Cancel'
                            : 'Cancel Editing',
                      ),
                    );
                    final saveButton = ElevatedButton.icon(
                      onPressed:
                          _isSaving ||
                              (_editingDistribution == null &&
                                  _isLoadingBeneficiaries)
                          ? null
                          : (_editingDistribution == null
                                ? _saveDistribution
                                : _updateDistribution),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _isSaving
                            ? (_editingDistribution == null
                                  ? 'Saving...'
                                  : 'Updating...')
                            : (_editingDistribution == null
                                  ? 'Save Distribution'
                                  : 'Update Distribution'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                    if (constraints.maxWidth < 400) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cancelButton,
                          const SizedBox(height: 10),
                          saveButton,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: cancelButton),
                        const SizedBox(width: 12),
                        Expanded(child: saveButton),
                      ],
                    );
                  },
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
        record['assistance_purpose'],
        record['source_agency'],
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

  Future<void> _viewDistributionCorrections(Map<String, dynamic> record) async {
    final id = _id(record['distribution_id']);
    List<Map<String, dynamic>> history;
    try {
      history = await DistributionService.fetchCorrectionHistory(id);
    } catch (error) {
      await _showFeedbackDialog(
        success: false,
        title: 'Unable to Load Corrections',
        message: _errorMessage(error),
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Distribution Correction History',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  'Distribution #$id · ${_text(record['household_head'])}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.greyText,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: history.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 22),
                          child: Center(
                            child: Text(
                              'No corrections have been made to this record.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.greyText),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: history.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final entry = history[index];
                            final before = Map<String, dynamic>.from(
                              entry['old_values'] as Map,
                            );
                            final after = Map<String, dynamic>.from(
                              entry['new_values'] as Map,
                            );
                            final changed = after.keys
                                .where(
                                  (key) =>
                                      '${after[key] ?? ''}' !=
                                      '${before[key] ?? ''}',
                                )
                                .toList();
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.borderColor,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Revision ${_text(entry['revision_after'])} · '
                                    '${_formatDate(entry['changed_at'])}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Staff ID: ${_text(entry['changed_by'])}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.greyText,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Reason: ${_text(entry['correction_reason'])}',
                                  ),
                                  const SizedBox(height: 10),
                                  for (final key in changed) ...[
                                    Text(
                                      key.replaceAll('_', ' ').toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.greyText,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${_text(before[key])}  →  ${_text(after[key])}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 6),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: SizedBox(
                    width: 150,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
              _chip(
                record['is_simulation'] == true ? 'Demo' : 'Recorded delivery',
                const Color(0xFF185C37),
              ),
              if (record['predicted_class'] != null)
                _chip(
                  '$vulnerability Vulnerability',
                  _classColor(vulnerability),
                ),
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
          if (record['amount_php'] != null)
            Text('Assistance amount: PHP ${_text(record['amount_php'])}')
          else
            Text(
              'Quantity: ${_text(record['quantity'])} '
              '${_text(record['unit'])}',
            ),
          const SizedBox(height: 5),
          Text('Reason / Need: ${_text(record['assistance_purpose'])}'),
          if (_text(record['source_agency']) != '—') ...[
            const SizedBox(height: 5),
            Text('Program / Source: ${_text(record['source_agency'])}'),
          ],
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
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _viewDistributionCorrections(record),
                icon: const Icon(Icons.history, size: 17),
                label: const Text('Correction History'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isSaving || _editingDistribution != null
                    ? null
                    : () => _editDistribution(record),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit Record'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.white,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionHistory() {
    final records = _filteredDistributions;

    return _sectionCard(
      title: 'Aid Distribution Records',
      subtitle: 'Assistance transactions and their history.',
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
            const AidTrackModuleLoading()
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
          'Record and review household assistance.',
          style: TextStyle(color: AppColors.greyText, fontSize: 13),
        ),

        const SizedBox(height: 20),

        if (_beneficiaries.any(
              (item) => item['assessment_data_origin'] == 'synthetic',
            ) ||
            _distributions.any((item) => item['is_simulation'] == true)) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 19,
                  color: AppColors.primaryGreen,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Demo data active. Sample transactions are not verified LGU releases.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        _buildDistributionForm(),

        const SizedBox(height: 22),

        _buildDistributionHistory(),
      ],
    );
  }
}
