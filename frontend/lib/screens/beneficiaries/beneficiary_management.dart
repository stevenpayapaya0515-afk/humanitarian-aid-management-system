import '../../widgets/aidtrack_section_card.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/beneficiary_service.dart';
import '../../widgets/aidtrack_module_loading.dart';

class BeneficiaryManagementScreen extends StatefulWidget {
  const BeneficiaryManagementScreen({super.key});

  @override
  State<BeneficiaryManagementScreen> createState() =>
      _BeneficiaryManagementScreenState();
}

class _BeneficiaryManagementScreenState
    extends State<BeneficiaryManagementScreen> {
  final _candidateSearchController = TextEditingController();
  final _beneficiarySearchController = TextEditingController();

  List<Map<String, dynamic>> _candidates = [];
  List<Map<String, dynamic>> _beneficiaries = [];

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _candidateSearchController.dispose();
    _beneficiarySearchController.dispose();
    super.dispose();
  }

  // ==========================================
  // HELPERS
  // ==========================================

  int _id(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String _value(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return '—';
    }
    return value.toString();
  }

  String _errorMessage(Object error) {
    if (error is AuthException) return error.message;

    if (error is TimeoutException) {
      return 'The server took too long to respond. Please try again.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to FastAPI. Check your backend.';
    }

    if (error is FormatException) {
      return 'The server returned unexpected data.';
    }

    return 'Unable to complete the request. Please check the backend.';
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'Date unavailable';

    final parsed = DateTime.tryParse(value.toString());

    if (parsed == null) return value.toString();

    final date = parsed.toLocal();

    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  Color _classColor(String value) {
    switch (value) {
      case 'High':
        return const Color(0xFFC62828);
      case 'Medium':
        return const Color(0xFFAC7900);
      case 'Low':
        return AppColors.primaryGreen;
      default:
        return AppColors.greyText;
    }
  }

  // ==========================================
  // SUCCESS AND ERROR FEEDBACK MODAL
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
        backgroundColor: AppColors.white,
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
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
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
        useRootNavigator: true,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.white,
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
                  'Saving Beneficiary Record...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please wait while the record is saved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.greyText, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // HANDLE BENEFICIARY SAVE OPERATIONS
  // ==========================================

  Future<void> _performBeneficiarySave({
    required Future<void> Function() request,
    required String successTitle,
    required String successMessage,
  }) async {
    if (_isSaving || _isLoading || !mounted) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    _showSavingDialog();

    bool saved = false;
    String? failureMessage;

    try {
      await request();
      saved = true;

      if (mounted) {
        await _loadRecords();
      }
    } catch (error) {
      failureMessage = _errorMessage(error);
    } finally {
      if (mounted) {
        // Close the loading modal.
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _isSaving = false;

          if (failureMessage != null) {
            _error = failureMessage;
          }
        });
      }
    }

    if (!mounted) return;

    if (!saved) {
      await _showFeedbackDialog(
        success: false,
        title: 'Operation Failed',
        message: failureMessage ?? 'An unexpected error occurred while saving.',
      );
      return;
    }

    await _showFeedbackDialog(
      success: true,
      title: successTitle,
      message: _error == null
          ? successMessage
          : '$successMessage The records could not be refreshed. '
                'Please click Refresh records.',
    );
  }

  // ==========================================
  // LOAD BENEFICIARY DATA
  // ==========================================

  Future<void> _loadRecords() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        BeneficiaryService.fetchCandidates(),
        BeneficiaryService.fetchBeneficiaries(),
      ]);

      if (!mounted) return;

      setState(() {
        _candidates = results[0];
        _beneficiaries = results[1];
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _errorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ==========================================
  // FILTER RECORDS
  // ==========================================

  List<Map<String, dynamic>> get _filteredCandidates {
    final query = _candidateSearchController.text.trim().toLowerCase();

    if (query.isEmpty) return _candidates;

    return _candidates.where((item) {
      final searchable = [
        item['household_id'],
        item['household_head'],
        item['barangay'],
        item['predicted_class'],
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredBeneficiaries {
    final query = _beneficiarySearchController.text.trim().toLowerCase();

    if (query.isEmpty) return _beneficiaries;

    return _beneficiaries.where((item) {
      final searchable = [
        item['beneficiary_id'],
        item['household_id'],
        item['household_head'],
        item['barangay'],
        item['status'],
        item['predicted_class'],
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  // Shared heading for the Beneficiary Management dialogs.
  Widget _dialogHeading({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.lightGreen,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.primaryGreen, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.greyText),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Consistent side-by-side actions, matching Household Registration.
  Widget _dialogActions({
    required BuildContext dialogContext,
    required String actionLabel,
    required VoidCallback? onAction,
  }) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 180,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              backgroundColor: AppColors.white,
              side: const BorderSide(color: AppColors.primaryGreen),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ),
        SizedBox(
          width: 180,
          child: ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(actionLabel, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // REGISTER BENEFICIARY FOR REVIEW
  // ==========================================

  Future<void> _registerBeneficiary(Map<String, dynamic> candidate) async {
    if (_isSaving || _isLoading) return;

    final householdId = _id(candidate['household_id']);
    final notesController = TextEditingController();

    final notes = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
        actionsPadding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        title: _dialogHeading(
          title: 'Register for Review',
          subtitle: 'Create a pending beneficiary review record',
          icon: Icons.person_add_alt_1_outlined,
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(color: AppColors.borderColor),
              const SizedBox(height: 12),
              Text(
                _value(candidate['household_head']),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('Household #$householdId', AppColors.primaryGreen),
                  _chip(
                    '${_value(candidate['predicted_class'])} Vulnerability',
                    _classColor(_value(candidate['predicted_class'])),
                  ),
                  if (candidate['assessment_data_origin'] == 'synthetic')
                    _chip('Practice record', AppColors.greyText),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Barangay: ${_value(candidate['barangay'])}  •  '
                'Assessment #${_value(candidate['assessment_id'])}',
                style: const TextStyle(fontSize: 12, color: AppColors.greyText),
              ),
              const SizedBox(height: 16),
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
                    Icon(
                      Icons.info_outline,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This creates a Pending review record. The Random Forest '
                        'classification does not automatically approve aid assistance.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: notesController,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Review notes (optional)',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          _dialogActions(
            dialogContext: dialogContext,
            actionLabel: 'Register for Review',
            onAction: () =>
                Navigator.pop(dialogContext, notesController.text.trim()),
          ),
        ],
      ),
    );

    notesController.dispose();
    if (!mounted || notes == null) return;

    await _performBeneficiarySave(
      request: () async {
        await BeneficiaryService.createBeneficiary(
          householdId: householdId,
          reviewNotes: notes,
        );
      },
      successTitle: 'Beneficiary Registered',
      successMessage:
          'The household has been successfully registered '
          'for beneficiary review with Pending status.',
    );
  }

  // ==========================================
  // UPDATE REVIEW STATUS
  // ==========================================

  Future<void> _useLatestAssessment(Map<String, dynamic> record) async {
    if (_isSaving || _isLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
        actionsPadding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
        title: _dialogHeading(
          title: 'Check Latest Assessment',
          subtitle: 'Check for a newer assessment and classification',
          icon: Icons.sync_outlined,
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(color: AppColors.borderColor),
              const SizedBox(height: 14),
              const Text(
                'This checks the latest saved household assessment and its '
                'Random Forest classification.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.darkText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lightGreen,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT BENEFICIARY REFERENCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Assessment #${_value(record['assessment_id'])}  •  '
                      'Classification #${_value(record['classification_id'])}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Review status: ${_value(record['status'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.greyText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 20, color: Color(0xFF9A7200)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'If a newer classified assessment is found, the beneficiary '
                      'returns to For Review. The previous decision stays in '
                      'review history. If nothing changed, the status stays the same.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          _dialogActions(
            dialogContext: dialogContext,
            actionLabel: 'Check Latest',
            onAction: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _performBeneficiarySave(
      request: () => BeneficiaryService.useLatestAssessment(record),
      successTitle: 'Assessment Link Checked',
      successMessage:
          'This beneficiary now uses its latest classification. If the link '
          'changed, the record was returned to For Review and the change '
          'was saved in history.',
    );
  }

  Future<void> _updateStatus(Map<String, dynamic> beneficiary) async {
    if (_isSaving || _isLoading) return;

    final beneficiaryId = _id(beneficiary['beneficiary_id']);
    final currentStatus = _value(beneficiary['status']);

    if (currentStatus == 'Approved' || currentStatus == 'Rejected') {
      await _showFeedbackDialog(
        success: false,
        title: 'Update Not Allowed',
        message: 'This is a finalized record. No changes are available here.',
      );
      return;
    }

    final notesController = TextEditingController(
      text: (beneficiary['review_notes'] ?? '').toString(),
    );
    bool reviewConfirmed = false;
    String selectedStatus = currentStatus == 'For Review'
        ? 'For Review'
        : 'Pending';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isFinalDecision =
              selectedStatus == 'Approved' || selectedStatus == 'Rejected';
          final canSave =
              !isFinalDecision ||
              (reviewConfirmed && notesController.text.trim().isNotEmpty);

          return AlertDialog(
            backgroundColor: AppColors.white,
            surfaceTintColor: AppColors.white,
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            actionsPadding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
            title: _dialogHeading(
              title: 'Update Beneficiary Review',
              subtitle: 'Record a manual Staff review decision',
              icon: Icons.fact_check_outlined,
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(color: AppColors.borderColor),
                  const SizedBox(height: 12),
                  Text(
                    _value(beneficiary['household_head']),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('Current: $currentStatus', AppColors.primaryGreen),
                      _chip(
                        '${_value(beneficiary['predicted_class'])} Vulnerability',
                        _classColor(_value(beneficiary['predicted_class'])),
                      ),
                      if (beneficiary['assessment_data_origin'] == 'synthetic')
                        _chip('Practice record', AppColors.greyText),
                    ],
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Review status',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'For Review',
                        child: Text('For Review'),
                      ),
                      DropdownMenuItem(
                        value: 'Approved',
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: 'Rejected',
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    maxLength: 1000,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: isFinalDecision
                          ? 'Decision reason (required)'
                          : 'Review notes (optional)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (isFinalDecision) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: reviewConfirmed,
                      onChanged: (value) => setDialogState(
                        () => reviewConfirmed = value ?? false,
                      ),
                      title: const Text(
                        'I reviewed the household information and recorded '
                        'my decision reason.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'The vulnerability classification supports Staff review; '
                    'it does not automatically decide aid eligibility.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.greyText,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              _dialogActions(
                dialogContext: dialogContext,
                actionLabel: 'Save Changes',
                onAction: canSave
                    ? () => Navigator.pop(dialogContext, {
                        'status': selectedStatus,
                        'review_notes': notesController.text.trim(),
                        'review_confirmed': reviewConfirmed.toString(),
                      })
                    : null,
              ),
            ],
          );
        },
      ),
    );

    notesController.dispose();
    if (!mounted || result == null) return;

    await _performBeneficiarySave(
      request: () async {
        await BeneficiaryService.updateBeneficiary(
          beneficiaryId: beneficiaryId,
          status: result['status']!,
          reviewNotes: result['review_notes']!,
          expectedAssessmentId: _id(beneficiary['assessment_id']),
          expectedClassificationId: _id(beneficiary['classification_id']),
          expectedStatus: currentStatus,
          reviewConfirmed: result['review_confirmed'] == 'true',
        );
      },
      successTitle: 'Beneficiary Status Updated',
      successMessage:
          'The beneficiary review status and notes '
          'have been successfully saved.',
    );
  }

  // ==========================================
  // VIEW REVIEW HISTORY
  // ==========================================

  Future<void> _showHistory(Map<String, dynamic> beneficiary) async {
    final beneficiaryId = _id(beneficiary['beneficiary_id']);
    final historyFuture = BeneficiaryService.fetchHistory(beneficiaryId);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
        actionsPadding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        title: _dialogHeading(
          title: 'Beneficiary Review History',
          subtitle: 'Saved Staff decisions and notes',
          icon: Icons.history_outlined,
        ),
        content: SizedBox(
          width: 460,
          height: 330,
          child: Column(
            children: [
              const Divider(color: AppColors.borderColor),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: historyFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryGreen,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          _errorMessage(snapshot.error!),
                          style: const TextStyle(color: Color(0xFFC62828)),
                        ),
                      );
                    }

                    final events = snapshot.data ?? [];
                    if (events.isEmpty) {
                      return const Center(
                        child: Text('No review history yet.'),
                      );
                    }

                    return ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderColor),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.history,
                                size: 20,
                                color: AppColors.primaryGreen,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_value(event['old_status'])} → '
                                      '${_value(event['new_status'])}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.darkText,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDate(event['changed_at']),
                                      style: const TextStyle(
                                        color: AppColors.greyText,
                                        fontSize: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _value(event['review_notes']),
                                      style: const TextStyle(
                                        color: AppColors.darkText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // UI COMPONENTS
  // ==========================================

  Widget _refreshButton() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: (_isLoading || _isSaving) ? null : _loadRecords,
        hoverColor: const Color(0xFFE5E7EB),
        splashColor: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Text(
                _isLoading ? 'Refreshing...' : 'Refresh records',
                style: const TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return AidTrackSectionCard(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 520;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
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
                  if (trailing != null && !isMobile) ...[
                    const SizedBox(width: 10),
                    trailing,
                  ],
                ],
              ),
              if (trailing != null && isMobile) ...[
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

  Widget _searchField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.greyText),
        prefixIcon: const Icon(Icons.search, color: AppColors.primaryGreen),
        filled: true,
        fillColor: const Color(0xFFF8FAF8),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFFD6E2D8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xFFD6E2D8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.5,
          ),
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 19),
              ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _recordIcon(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFE9F5EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: AppColors.primaryGreen),
    );
  }

  Widget _recordSurface(Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFD6E2D8)),
      ),
      child: child,
    );
  }

  Widget _reviewNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F8F2),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFD6E2D8)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: AppColors.primaryGreen),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Review the household information, then record your decision. '
              'Use latest assessment when new information is available. '
              'A vulnerability classification does not automatically approve aid.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.darkText,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              color: AppColors.greyText,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.greyText, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // CANDIDATE CARD
  // ==========================================

  Widget _buildCandidateCard(Map<String, dynamic> candidate) {
    final predictedClass = _value(candidate['predicted_class']);

    return _recordSurface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _recordIcon(Icons.home_work_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _value(candidate['household_head']),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Household #${_value(candidate['household_id'])} '
                      '• ${_value(candidate['barangay'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.greyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                '$predictedClass Vulnerability',
                _classColor(predictedClass),
              ),
              if (candidate['assessment_data_origin'] == 'synthetic')
                _chip('Practice record', AppColors.greyText),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Assessment #${_value(candidate['assessment_id'])} '
            '• Household Size: ${_value(candidate['household_size'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.greyText),
          ),
          const SizedBox(height: 4),
          Text(
            'Classification #${_value(candidate['classification_id'])} '
            '• ${_value(candidate['prediction_status'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.greyText),
          ),
          const Divider(height: 24, color: Color(0xFFE4EBE5)),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _isSaving || _isLoading
                  ? null
                  : () => _registerBeneficiary(candidate),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Register for Review'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryGreen,
                side: const BorderSide(color: AppColors.primaryGreen),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // EXISTING BENEFICIARY CARD
  // ==========================================

  Widget _buildBeneficiaryCard(Map<String, dynamic> beneficiary) {
    final status = _value(beneficiary['status']);
    final predictedClass = _value(beneficiary['predicted_class']);

    final statusColor = status == 'Approved'
        ? AppColors.primaryGreen
        : status == 'Rejected'
        ? const Color(0xFFC62828)
        : status == 'For Review'
        ? const Color(0xFFAC7900)
        : AppColors.greyText;

    return _recordSurface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _recordIcon(Icons.fact_check_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _value(beneficiary['household_head']),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Beneficiary #${_value(beneficiary['beneficiary_id'])} '
                      '• Household #${_value(beneficiary['household_id'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.greyText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(status, statusColor),
              _chip(
                '$predictedClass Vulnerability',
                _classColor(predictedClass),
              ),
              if (beneficiary['assessment_data_origin'] == 'synthetic')
                _chip('Practice record', AppColors.greyText),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_value(beneficiary['barangay'])} '
            '• Assessment #${_value(beneficiary['assessment_id'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.greyText),
          ),
          const SizedBox(height: 5),
          Text(
            'Review Notes: ${_value(beneficiary['review_notes'])}',
            style: const TextStyle(fontSize: 12, color: AppColors.greyText),
          ),
          const SizedBox(height: 5),
          Text(
            beneficiary['assessment_data_origin'] == 'synthetic'
                ? 'Practice record'
                : 'LGU household assessment',
            style: const TextStyle(fontSize: 12, color: AppColors.greyText),
          ),
          const Divider(height: 24, color: Color(0xFFE4EBE5)),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isSaving ? null : () => _showHistory(beneficiary),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('View History'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: AppColors.primaryGreen),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _isSaving || _isLoading
                    ? null
                    : () => _useLatestAssessment(beneficiary),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Use latest assessment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                  side: const BorderSide(color: Color(0xFFD6E2D8)),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (status == 'Pending' || status == 'For Review')
                OutlinedButton.icon(
                  onPressed: _isSaving || _isLoading
                      ? null
                      : () => _updateStatus(beneficiary),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Update Review'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
                    minimumSize: const Size(0, 40),
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

  // ==========================================
  // MAIN SCREEN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final candidates = _filteredCandidates;
    final beneficiaries = _filteredBeneficiaries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The Staff Dashboard already shows this module's page heading.
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8B4B0)),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _sectionCard(
          title: 'Households for Beneficiary Review',
          subtitle:
              'Select a classified household to register for manual review.',
          icon: Icons.people_outline,
          trailing: _refreshButton(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reviewNotice(),
              const SizedBox(height: 14),
              _searchField(
                controller: _candidateSearchController,
                hint: 'Search household name, ID, or barangay...',
              ),
              const SizedBox(height: 12),
              Text(
                candidates.length == _candidates.length
                    ? '${candidates.length} available households'
                    : '${candidates.length} of ${_candidates.length} available households',
                style: const TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const AidTrackModuleLoading()
              else if (candidates.isEmpty)
                _emptyMessage(
                  _candidates.isEmpty
                      ? 'No households available for review.'
                      : 'No matching households found.',
                )
              else
                ...candidates.map(_buildCandidateCard),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionCard(
          title: 'Beneficiary Records',
          subtitle: 'View and update registered household review statuses.',
          icon: Icons.assignment_turned_in_outlined,
          trailing: _refreshButton(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchField(
                controller: _beneficiarySearchController,
                hint: 'Search beneficiary, status, or barangay...',
              ),
              const SizedBox(height: 12),
              Text(
                beneficiaries.length == _beneficiaries.length
                    ? '${beneficiaries.length} beneficiary records'
                    : '${beneficiaries.length} of ${_beneficiaries.length} beneficiary records',
                style: const TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (_isLoading)
                const AidTrackModuleLoading()
              else if (beneficiaries.isEmpty)
                _emptyMessage(
                  _beneficiaries.isEmpty
                      ? 'No beneficiary review records yet.'
                      : 'No matching beneficiary records found.',
                )
              else
                ...beneficiaries.map(_buildBeneficiaryCard),
            ],
          ),
        ),
      ],
    );
  }
}
