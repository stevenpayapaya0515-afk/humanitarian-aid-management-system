import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/beneficiary_service.dart';

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
        title: const Text('Register for Beneficiary Review'),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _value(candidate['household_head']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text('Household ID: $householdId'),
              Text('Barangay: ${_value(candidate['barangay'])}'),
              Text(
                'Predicted vulnerability: '
                '${_value(candidate['predicted_class'])}',
              ),
              const SizedBox(height: 16),
              const Text(
                'This registers the household as Pending. '
                'It does not approve aid eligibility.',
                style: TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
              const SizedBox(height: 16),
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
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, notesController.text.trim()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.white,
              backgroundColor: AppColors.primaryGreen,
            ),
            child: const Text('Register for Review'),
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

  Future<void> _updateStatus(Map<String, dynamic> beneficiary) async {
    if (_isSaving || _isLoading) return;

    final beneficiaryId = _id(beneficiary['beneficiary_id']);
    final currentStatus = _value(beneficiary['status']);

    // Finalized records cannot be changed through this
    // preliminary review interface.
    if (currentStatus == 'Approved' || currentStatus == 'Rejected') {
      await _showFeedbackDialog(
        success: false,
        title: 'Update Not Allowed',
        message:
            'This is a finalized record. '
            'No changes are available here.',
      );
      return;
    }

    final notesController = TextEditingController(
      text: (beneficiary['review_notes'] ?? '').toString(),
    );

    String selectedStatus = currentStatus == 'For Review'
        ? 'For Review'
        : 'Pending';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.white,
            title: const Text('Update Beneficiary Review'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _value(beneficiary['household_head']),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Review Status',
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
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedStatus = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Review Notes',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Final approval is unavailable while the '
                    'classification data is synthetic or preliminary.',
                    style: TextStyle(color: AppColors.greyText, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, {
                  'status': selectedStatus,
                  'review_notes': notesController.text.trim(),
                }),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.white,
                  backgroundColor: AppColors.primaryGreen,
                ),
                child: const Text('Save Changes'),
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
        title: const Text('Beneficiary Review History'),
        content: SizedBox(
          width: 500,
          height: 320,
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
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }

              final events = snapshot.data ?? [];

              if (events.isEmpty) {
                return const Center(
                  child: Text('No review history available.'),
                );
              }

              return ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  final event = events[index];

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.history,
                      color: AppColors.primaryGreen,
                    ),
                    title: Text(
                      '${_value(event['old_status'])} → '
                      '${_value(event['new_status'])}',
                    ),
                    subtitle: Text(
                      '${_formatDate(event['changed_at'])}\n'
                      '${_value(event['review_notes'])}',
                    ),
                    isThreeLine: true,
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
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
          final isMobile = constraints.maxWidth < 520;

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
                  if (trailing != null && !isMobile) ...[
                    const SizedBox(width: 12),
                    trailing,
                  ],
                ],
              ),
              if (trailing != null && isMobile) ...[
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

  Widget _searchField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: const Color(0xFFF5F8F5),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close),
              ),
      ),
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

  Widget _emptyMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.greyText, fontSize: 13),
        ),
      ),
    );
  }

  // ==========================================
  // CANDIDATE CARD
  // ==========================================

  Widget _buildCandidateCard(Map<String, dynamic> candidate) {
    final predictedClass = _value(candidate['predicted_class']);

    return Container(
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
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _value(candidate['household_head']),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
              _chip(
                '$predictedClass Vulnerability',
                _classColor(predictedClass),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Household #${_value(candidate['household_id'])} '
            '• ${_value(candidate['barangay'])}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Assessment #${_value(candidate['assessment_id'])} '
            '• Household Size: ${_value(candidate['household_size'])}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Prediction Status: '
            '${_value(candidate['prediction_status'])}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSaving || _isLoading
                ? null
                : () => _registerBeneficiary(candidate),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Register for Review'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: const BorderSide(color: AppColors.primaryGreen),
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

    return Container(
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
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _value(beneficiary['household_head']),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
              _chip(status, statusColor),
              _chip(
                '$predictedClass Vulnerability',
                _classColor(predictedClass),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Beneficiary #${_value(beneficiary['beneficiary_id'])} '
            '• Household #${_value(beneficiary['household_id'])}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '${_value(beneficiary['barangay'])} '
            '• Assessment #${_value(beneficiary['assessment_id'])}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Review Notes: ${_value(beneficiary['review_notes'])}',
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 14),
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
                ),
              ),
              if (status == 'Pending' || status == 'For Review')
                OutlinedButton.icon(
                  onPressed: _isSaving || _isLoading
                      ? null
                      : () => _updateStatus(beneficiary),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Update Status'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                    side: const BorderSide(color: AppColors.primaryGreen),
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
        const Text(
          'Beneficiary Management',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Manage household beneficiary review records and status history.',
          style: TextStyle(fontSize: 13, color: AppColors.greyText),
        ),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(14),
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
                  'Testing mode: vulnerability results are '
                  'preliminary and based on synthetic training data. '
                  'Beneficiary registration is not official aid approval.',
                  style: TextStyle(fontSize: 12, color: AppColors.darkText),
                ),
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB71C1C)),
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ======================================
        // AVAILABLE HOUSEHOLDS
        // ======================================
        _sectionCard(
          title: 'Households for Beneficiary Review',
          subtitle:
              'Select a classified household to register for manual review.',
          icon: Icons.people_outline,
          trailing: _refreshButton(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchField(
                controller: _candidateSearchController,
                hint: 'Search household name, ID, or barangay...',
              ),
              const SizedBox(height: 14),
              Text(
                '${candidates.length} available households',
                style: const TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                )
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

        const SizedBox(height: 22),

        // ======================================
        // REGISTERED BENEFICIARIES
        // ======================================
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
              const SizedBox(height: 14),
              Text(
                '${beneficiaries.length} beneficiary records',
                style: const TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                )
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
