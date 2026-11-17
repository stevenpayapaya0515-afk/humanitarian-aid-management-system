import '../../widgets/aidtrack_section_card.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/aidtrack_module_loading.dart';

// Registration, editing, member viewing, and deletion in one screen.
class HouseholdRegistration extends StatefulWidget {
  // Admin uses view-only mode; Staff keeps registration and editing.
  final bool readOnly;

  const HouseholdRegistration({super.key, this.readOnly = false});

  @override
  State<HouseholdRegistration> createState() => _HouseholdRegistrationState();
}

class _HouseholdRegistrationState extends State<HouseholdRegistration> {
  // Display Cancel and the action beside each other.
  Widget _buildActionButtons({
    String cancelLabel = 'Cancel',
    required String actionLabel,
    required VoidCallback? onCancel,
    required VoidCallback? onConfirm,
    Color actionColor = const Color(0xFF175C3A),
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          children: [
            // LEFT: White Cancel button with green border.
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF175C3A),
                    side: const BorderSide(color: Color(0xFF175C3A)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(cancelLabel, textAlign: TextAlign.center),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // RIGHT: Solid-colored action button.
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(actionLabel, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final _formKey = GlobalKey<FormState>();
  final _headController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityMunicipalityController = TextEditingController();
  final _barangayController = TextEditingController();
  final _purokController = TextEditingController();
  final _sizeController = TextEditingController();
  final _membersController = TextEditingController();

  List<Map<String, dynamic>> _households = [];
  String _searchText = '';
  String? _formError;
  String? _listError;
  int? _editingHouseholdId;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _setDefaultLocation();
    _sizeController.text = '1';
    _loadHouseholds();
  }

  @override
  void dispose() {
    _headController.dispose();
    _provinceController.dispose();
    _cityMunicipalityController.dispose();
    _barangayController.dispose();
    _purokController.dispose();
    _sizeController.dispose();
    _membersController.dispose();
    super.dispose();
  }

  // Default to the LGU locality; Staff can edit both fields if needed.
  void _setDefaultLocation() {
    _provinceController.text = 'Agusan del Norte';
    _cityMunicipalityController.text = 'Cabadbaran City';
  }

  // Match FastAPI's display-only full_address formatting.
  String _formatAddress({
    required String province,
    required String cityMunicipality,
    required String barangay,
    String? purok,
  }) {
    return [purok, barangay, cityMunicipality, province]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
  }

  String _displayAddress(Map<String, dynamic> household) {
    final fullAddress = household['full_address'];
    if (fullAddress is String && fullAddress.trim().isNotEmpty) {
      return fullAddress;
    }
    return _formatAddress(
      province: '${household['province'] ?? ''}',
      cityMunicipality: '${household['city_municipality'] ?? ''}',
      barangay: '${household['barangay'] ?? ''}',
      purok: household['purok']?.toString(),
    );
  }

  // One nonblank line represents one OTHER household member.
  // The head is already recorded in the Household head field.
  List<String> _enteredMembers() {
    return _membersController.text
        .split(RegExp(r'\r?\n'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  // Read the newline-separated text stored in households.household_member.
  List<String> _savedMembers(Map<String, dynamic> household) {
    return (household['household_member'] as String)
        .split(RegExp(r'\r?\n'))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Map<String, String> _headers() {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw const AuthException('Please log in again.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  void _checkResponse(http.Response response, int expectedCode) {
    if (response.statusCode == expectedCode) return;

    if (response.statusCode == 401) {
      throw const AuthException(
        'Your session has expired. Please log out and log in again.',
      );
    }

    if (response.statusCode == 403) {
      throw const AuthException('Your account cannot access this feature.');
    }

    if (response.statusCode == 404 || response.statusCode == 409) {
      final body = jsonDecode(response.body);

      throw AuthException(
        body['detail'] is String ? body['detail'] : 'The action failed.',
      );
    }

    if (response.statusCode == 422) {
      throw const AuthException(
        'Check the required household and location fields. Household size '
        'must match the head plus the other members; each name must be '
        'at most 100 characters.',
      );
    }

    throw AuthException('Request failed (${response.statusCode}).');
  }

  // Return a safe message for a failed request.
  String _errorMessage(Object error, {bool saving = false}) {
    if (error is AuthException) return error.message;

    if (saving) {
      return 'Unable to confirm the change. Check the connection and '
          'refresh the records before trying again.';
    }

    if (error is TimeoutException) {
      return 'Loading timed out. Click refresh.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to the server. Check your backend.';
    }

    return 'Unable to load records. Check the backend terminal, then refresh.';
  }

  // ========================================
  // LOAD RECORDS
  // ========================================

  Future<void> _loadHouseholds() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _listError = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/households'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);

      final decoded = jsonDecode(response.body) as List;

      final records = decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;

      setState(() => _households = records);
    } catch (error) {
      if (mounted) {
        setState(() => _listError = _errorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ========================================
  // EDIT AND RESET
  // ========================================

  void _clearForm() {
    _formKey.currentState?.reset();

    for (final controller in [
      _headController,
      _provinceController,
      _cityMunicipalityController,
      _barangayController,
      _purokController,
      _sizeController,
      _membersController,
    ]) {
      controller.clear();
    }

    _setDefaultLocation();
    _sizeController.text = '1';
    setState(() {
      _editingHouseholdId = null;
      _formError = null;
    });
  }

  void _startEditing(Map<String, dynamic> household) {
    if (_isSaving || _isLoading) return;

    _formKey.currentState?.reset();

    _headController.text = '${household['household_head']}';
    _provinceController.text = '${household['province'] ?? ''}';
    _cityMunicipalityController.text =
        '${household['city_municipality'] ?? ''}';
    _barangayController.text = '${household['barangay']}';
    _purokController.text = '${household['purok'] ?? ''}';

    // Keep an old record's size; do not silently shrink it to one person.
    _sizeController.text = '${household['household_size']}';

    _membersController.text = household['household_member'] as String;

    setState(() {
      _editingHouseholdId = household['household_id'] as int;
      _formError = null;
    });

    final formContext = _formKey.currentContext;

    if (formContext != null) {
      Scrollable.ensureVisible(
        formContext,
        duration: const Duration(milliseconds: 300),
        alignment: 0,
      );
    }
  }

  // ==========================================
  // REGISTER OR UPDATE HOUSEHOLD
  // ==========================================

  Future<void> _saveHousehold() async {
    if (_isSaving || _isLoading) return;

    // Validate the registration form first.
    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showFeedbackDialog(
        success: false,
        title: 'Invalid Household Information',
        message:
            'Please complete the required fields and '
            'correct the highlighted errors.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    final editingId = _editingHouseholdId;

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    // Display the loading modal.
    _showSavingDialog(
      editingId == null ? 'Registering Household...' : 'Updating Household...',
    );

    bool savedSuccessfully = false;
    String? failureMessage;

    try {
      final purok = _purokController.text.trim();

      final body = jsonEncode({
        'household_head': _headController.text.trim(),
        'province': _provinceController.text.trim(),
        'city_municipality': _cityMunicipalityController.text.trim(),
        'barangay': _barangayController.text.trim(),
        'purok': purok.isEmpty ? null : purok,
        'household_size': int.parse(_sizeController.text.trim()),
        'household_member': _enteredMembers().join('\n'),
      });

      final http.Response response;

      if (editingId == null) {
        // REGISTER HOUSEHOLD
        response = await http
            .post(
              Uri.parse('${AuthService.baseUrl}/households'),
              headers: _headers(),
              body: body,
            )
            .timeout(const Duration(seconds: 15));
      } else {
        // UPDATE HOUSEHOLD
        response = await http
            .patch(
              Uri.parse('${AuthService.baseUrl}/households/$editingId'),
              headers: _headers(),
              body: body,
            )
            .timeout(const Duration(seconds: 15));
      }

      _checkResponse(response, editingId == null ? 201 : 200);

      savedSuccessfully = true;

      if (!mounted) return;

      _clearForm();

      // Refresh the registered household records.
      await _loadHouseholds();
    } catch (error) {
      failureMessage = _errorMessage(error, saving: true);

      if (mounted) {
        setState(() {
          _formError = failureMessage;
        });
      }
    } finally {
      if (mounted) {
        // Close the loading modal.
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _isSaving = false;
        });
      }
    }

    if (!mounted) return;

    if (!savedSuccessfully) {
      await _showFeedbackDialog(
        success: false,
        title: editingId == null
            ? 'Household Registration Failed'
            : 'Household Update Failed',
        message: failureMessage ?? 'Unable to save the household record.',
      );
      return;
    }

    // Show the success modal.
    await _showFeedbackDialog(
      success: true,
      title: editingId == null ? 'Household Registered' : 'Household Updated',
      message: _listError == null
          ? 'The household and member information '
                'have been successfully saved.'
          : 'The household was saved, but the records '
                'could not be refreshed. Please click Refresh.',
    );
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

  void _showSavingDialog(String title) {
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please wait while the request is processed.',
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

  // ========================================
  // VIEW MEMBERS
  // ========================================

  Future<void> _viewMembers(Map<String, dynamic> household) async {
    final names = <String>[
      household['household_head'] as String,
      ..._savedMembers(household),
    ];
    final isComplete = household['members_complete'] == true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        surfaceTintColor: AppColors.white,
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.groups_outlined,
                color: AppColors.primaryGreen,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Household Members',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Registered member information',
                    style: TextStyle(fontSize: 12, color: AppColors.greyText),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(color: AppColors.borderColor),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.lightGreen,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      'Registered size: ${household['household_size']}',
                      style: const TextStyle(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isComplete
                          ? const Color(0xFFEAF6EE)
                          : const Color(0xFFFFF5E6),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      isComplete ? 'Complete roster' : 'Incomplete roster',
                      style: TextStyle(
                        color: isComplete
                            ? AppColors.primaryGreen
                            : const Color(0xFF995D14),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (!isComplete) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8EC),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFF1D5AC)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF995D14),
                        size: 19,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          widget.readOnly
                              ? 'Member list incomplete. Ask authorized Staff to verify '
                                    'the names and household size.'
                              : 'Member list incomplete. Use Edit to enter the missing '
                                    'names and verify the household size.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF805016),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'MEMBER LIST',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.greyText,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < names.length; index++) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.lightGreen,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              names[index],
                              softWrap: true,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              index == 0
                                  ? 'Household head'
                                  : 'Household member',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.greyText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < names.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              minimumSize: const Size(120, 42),
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
  // DELETE HOUSEHOLD
  // ==========================================

  Future<void> _deleteHousehold(Map<String, dynamic> household) async {
    if (_isSaving || _isLoading) return;

    // Ask for confirmation before deleting.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Household?', textAlign: TextAlign.center),
        content: Text(
          'Delete the household of '
          '${household['household_head']} and its '
          'member list?\n\nThis cannot be undone.',
          textAlign: TextAlign.center,
        ),
        actions: [
          _buildActionButtons(
            actionLabel: 'Delete Household',
            actionColor: const Color(0xFFB71C1C),
            onCancel: () {
              Navigator.pop(dialogContext, false);
            },
            onConfirm: () {
              Navigator.pop(dialogContext, true);
            },
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || _isSaving || _isLoading) {
      return;
    }

    setState(() {
      _isSaving = true;
      _listError = null;
    });

    // Show loading modal.
    _showSavingDialog('Deleting Household...');

    bool deletedSuccessfully = false;
    String? failureMessage;

    try {
      final id = household['household_id'];

      final response = await http
          .delete(
            Uri.parse('${AuthService.baseUrl}/households/$id'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);

      deletedSuccessfully = true;

      if (!mounted) return;

      if (_editingHouseholdId == id) {
        _clearForm();
      }

      // Refresh records after successful deletion.
      await _loadHouseholds();
    } catch (error) {
      failureMessage = _errorMessage(error, saving: true);
    } finally {
      if (mounted) {
        // Close the loading modal.
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _isSaving = false;
        });
      }
    }

    if (!mounted) return;

    // Show error if the deletion failed.
    if (!deletedSuccessfully) {
      await _showFeedbackDialog(
        success: false,
        title: 'Household Deletion Failed',
        message: failureMessage ?? 'Unable to delete the household.',
      );
      return;
    }

    // Show successful deletion.
    await _showFeedbackDialog(
      success: true,
      title: 'Household Deleted',
      message: _listError == null
          ? 'The household record has been '
                'successfully deleted.'
          : 'The household was deleted, but the '
                'records could not be refreshed.',
    );
  }

  // ========================================
  // FORM APPEARANCE
  // ========================================

  Widget _card(Widget child) => AidTrackSectionCard(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    child: child,
  );

  // Match the section heading and description used in Household Assessment.
  Widget _buildSectionIntro({
    required String title,
    required String description,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF263238),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: AppColors.greyText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int? maxLength,
    bool optional = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_isSaving,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      counterText: '',
    ),
    validator: (value) {
      if (!optional && (value == null || value.trim().isEmpty)) {
        return 'Please complete this field.';
      }
      return null;
    },
  );

  Widget _buildRegistrationForm() => _card(
    Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _editingHouseholdId == null
                ? 'Register Household'
                : 'Edit Household',
            style: const TextStyle(
              color: Color(0xFF263238),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Register the household head and all other members. The total is '
            'calculated automatically and used to validate Household Assessment.',
            style: TextStyle(color: AppColors.greyText, fontSize: 13),
          ),
          const SizedBox(height: 20),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 650
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;

              final fields = <Widget>[
                _textField(
                  controller: _headController,
                  label: 'Household head',
                  icon: Icons.person_outline,
                  maxLength: 100,
                ),
                _textField(
                  controller: _provinceController,
                  label: 'Province',
                  icon: Icons.map_outlined,
                  maxLength: 100,
                ),
                _textField(
                  controller: _cityMunicipalityController,
                  label: 'City / Municipality',
                  icon: Icons.location_city_outlined,
                  maxLength: 100,
                ),
                _textField(
                  controller: _barangayController,
                  label: 'Barangay',
                  icon: Icons.place_outlined,
                  maxLength: 100,
                ),
                _textField(
                  controller: _purokController,
                  label: 'Purok / Sitio (optional)',
                  icon: Icons.pin_drop_outlined,
                  maxLength: 100,
                  optional: true,
                ),
                TextFormField(
                  controller: _sizeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Total household members',
                    helperText: 'Calculated from the head and member names.',
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                  validator: (value) {
                    final size = int.tryParse(value?.trim() ?? '');

                    if (size == null || size < 1 || size > 2147483647) {
                      return 'Enter a valid whole number of at least 1.';
                    }

                    return null;
                  },
                ),
              ];

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: fields
                    .map((field) => SizedBox(width: width, child: field))
                    .toList(),
              );
            },
          ),

          const SizedBox(height: 20),

          const Text(
            'Household Members',
            style: TextStyle(
              color: Color(0xFF263238),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Enter one full name per line. Do not repeat the household head. '
            'For a one-person household, leave this blank.',
            style: TextStyle(color: AppColors.greyText),
          ),

          const SizedBox(height: 12),

          TextFormField(
            controller: _membersController,
            enabled: !_isSaving,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: (_) {
              _sizeController.text = '${_enteredMembers().length + 1}';
              setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'Member full names',
              alignLabelWithHint: true,
              hintText: 'Example Member One\nExample Member Two',
            ),
            validator: (_) {
              final names = _enteredMembers();

              if (names.any((name) => name.length > 100)) {
                return 'Each full name must be at most 100 characters.';
              }

              final size = int.tryParse(_sizeController.text.trim());

              if (size != null && size != names.length + 1) {
                return 'You listed ${names.length} other members plus 1 head. '
                    'The names must match the household size.';
              }

              return null;
            },
          ),

          const SizedBox(height: 8),

          Text(
            '1 household head + ${_enteredMembers().length} other members '
            '= ${_enteredMembers().length + 1} people',
            style: const TextStyle(color: AppColors.greyText),
          ),

          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(_formError!, style: const TextStyle(color: Colors.red)),
          ],

          const SizedBox(height: 20),

          // Editing: Cancel on the left and Update on the right.
          if (_editingHouseholdId != null)
            _buildActionButtons(
              cancelLabel: 'Cancel Editing',
              actionLabel: _isSaving ? 'Saving...' : 'Update Household',
              onCancel: _isSaving || _isLoading ? null : _clearForm,
              onConfirm: _isSaving || _isLoading ? null : _saveHousehold,
            )
          else
            // Creating: keep the single Register Household button.
            ElevatedButton.icon(
              onPressed: _isSaving || _isLoading ? null : _saveHousehold,
              icon: const Icon(Icons.add_home_outlined),
              label: Text(_isSaving ? 'Saving...' : 'Register Household'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ========================================
  // SEARCH AND HOUSEHOLD TABLE
  // ========================================

  Widget _buildRecords() {
    final query = _searchText.trim().toLowerCase();

    final filtered = _households.where((household) {
      final searchable = [
        household['household_id'],
        household['household_head'],
        household['province'],
        household['city_municipality'],
        household['barangay'],
        household['purok'],
        _displayAddress(household),
        ..._savedMembers(household),
      ];

      return searchable.any(
        (value) => '${value ?? ''}'.toLowerCase().contains(query),
      );
    }).toList();

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registered Household Records',
                      style: TextStyle(
                        color: Color(0xFF263238),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Search, view, and manage registered household information.',
                      style: TextStyle(color: AppColors.greyText, fontSize: 13),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _isLoading || _isSaving ? null : _loadHouseholds,

                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryGreen,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 18),

                label: Text(_isLoading ? 'Refreshing...' : 'Refresh'),

                style: ButtonStyle(
                  foregroundColor: const WidgetStatePropertyAll(
                    AppColors.primaryGreen,
                  ),
                  backgroundColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  overlayColor: WidgetStateProperty.resolveWith<Color?>((
                    states,
                  ) {
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed)) {
                      return AppColors.lightGreen;
                    }

                    return Colors.transparent;
                  }),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          TextField(
            onChanged: (value) => setState(() => _searchText = value),
            decoration: InputDecoration(
              hintText: 'Search households or member names...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF5F8F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (_isLoading)
            const AidTrackModuleLoading()
          else if (_listError != null)
            Text(_listError!, style: const TextStyle(color: Colors.red))
          else if (_households.isEmpty)
            const Text('No households registered yet.')
          else if (filtered.isEmpty)
            const Text('No households match your search.')
          else ...[
            Text(
              '${filtered.length} of ${_households.length} households',
              style: const TextStyle(color: AppColors.greyText),
            ),

            const SizedBox(height: 8),

            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    // Reduce spacing so the Actions column has more room.
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    columns: [
                      const DataColumn(label: Text('ID')),
                      const DataColumn(label: Text('Household Head')),
                      const DataColumn(label: Text('Barangay')),
                      const DataColumn(label: Text('Purok')),
                      const DataColumn(
                        label: Text('Household Size'),
                        headingRowAlignment: MainAxisAlignment.center,
                      ),
                      const DataColumn(label: Text('Full Address')),

                      // Header above the View Members button.
                      const DataColumn(
                        label: Text('Household Members'),
                        headingRowAlignment: MainAxisAlignment.center,
                      ),

                      // Only Staff mode displays the Actions column.
                      if (!widget.readOnly)
                        const DataColumn(
                          label: Text('Actions'),
                          headingRowAlignment: MainAxisAlignment.center,
                        ),
                    ],
                    rows: filtered.map((household) {
                      return DataRow(
                        cells: [
                          DataCell(Text('${household['household_id']}')),
                          DataCell(Text('${household['household_head']}')),
                          DataCell(Text('${household['barangay']}')),
                          DataCell(Text('${household['purok'] ?? '—'}')),
                          DataCell(
                            Center(
                              child: Text('${household['household_size']}'),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 230,
                              child: Tooltip(
                                message: _displayAddress(household),
                                child: Text(
                                  _displayAddress(household),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),

                          // Separate cell for viewing household members.
                          DataCell(
                            Center(
                              child: TextButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () => _viewMembers(household),
                                icon: const Icon(
                                  Icons.people_outline,
                                  size: 18,
                                ),
                                label: const Text('View Members'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primaryGreen,
                                ),
                              ),
                            ),
                          ),

                          // Hide Edit and Delete in Admin mode.
                          if (!widget.readOnly)
                            DataCell(
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _startEditing(household),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('Edit'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.primaryGreen,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _deleteHousehold(household),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                      ),
                                      label: const Text('Delete'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFFB71C1C,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // The dashboard supplies the surrounding page and vertical scrolling.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Same title-and-description starting point as Household Assessment.
        _buildSectionIntro(
          title: widget.readOnly
              ? 'Household Records'
              : 'Household Registration',
          description: widget.readOnly
              ? 'View registered household information and member records.'
              : 'Record household information for registration and future '
                    'vulnerability assessment.',
        ),

        // Show the registration form only in Staff mode.
        if (!widget.readOnly) ...[
          _buildRegistrationForm(),
          const SizedBox(height: 24),
        ],

        // Both Admin and Staff can search and view household records.
        _buildRecords(),
      ],
    );
  }
}
