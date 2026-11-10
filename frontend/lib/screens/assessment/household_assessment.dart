import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/vulnerability_service.dart';

class HouseholdAssessmentScreen extends StatefulWidget {
  const HouseholdAssessmentScreen({super.key});

  @override
  State<HouseholdAssessmentScreen> createState() =>
      _HouseholdAssessmentScreenState();
}

class _HouseholdAssessmentScreenState extends State<HouseholdAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();

  // Household population controllers.
  final _age0to5Controller = TextEditingController(text: '0');
  final _age6to17Controller = TextEditingController(text: '0');
  final _age18to59Controller = TextEditingController(text: '0');
  final _age60PlusController = TextEditingController(text: '0');
  final _pwdController = TextEditingController(text: '0');

  // Beneficiary record.
  final _beneficiaryStatusController = TextEditingController(text: 'Pending');

  // Dropdown values matching the training dataset.
  static const List<String> _incomeRanges = [
    'Below 5000',
    '5000-9999',
    '10000-19999',
    '20000-29999',
    '30000 and above',
  ];

  static const List<String> _employmentOptions = [
    'Employed',
    'Self-employed',
    'Irregular work',
    'Unemployed',
    'Retired',
  ];

  static const List<String> _livelihoodOptions = [
    'Farming',
    'Fishing',
    'Daily wage',
    'Daily wage employment',
    'Vending',
    'Small business',
    'Salaried employment',
    'Remittances',
    'Pension',
    'No current livelihood',
  ];

  static const List<String> _damageOptions = ['Minor', 'Major', 'Destroyed'];

  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _assessments = [];

  Map<String, dynamic>? _selectedHousehold;

  DateTime _assessmentDate = DateTime.now();

  String? _monthlyIncomeRange;
  String? _employmentStatus;
  String? _livelihoodType;
  String _housingDamageLevel = 'Minor';

  bool _previousAssistance = false;
  bool _disasterAffected = false;
  bool _displaced = false;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRefreshingAssessments = false;

  String? _loadError;
  String? _assessmentRefreshError;
  String? _formError;

  @override
  void initState() {
    super.initState();

    // Update the population total while staff enters values.
    for (final controller in [
      _age0to5Controller,
      _age6to17Controller,
      _age18to59Controller,
      _age60PlusController,
      _pwdController,
      _beneficiaryStatusController,
    ]) {
      controller.addListener(_onFormChanged);
    }

    _loadData();
  }

  @override
  void dispose() {
    _age0to5Controller.dispose();
    _age6to17Controller.dispose();
    _age18to59Controller.dispose();
    _age60PlusController.dispose();
    _pwdController.dispose();
    _beneficiaryStatusController.dispose();

    super.dispose();
  }

  // ==========================================
  // FORM HELPERS
  // ==========================================

  void _onFormChanged() {
    if (!mounted) return;

    setState(() {
      _formError = null;
    });
  }

  int _number(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
  }

  int get _ageGroupTotal =>
      _number(_age0to5Controller) +
      _number(_age6to17Controller) +
      _number(_age18to59Controller) +
      _number(_age60PlusController);

  int get _expectedHouseholdSize =>
      (_selectedHousehold?['household_size'] as num?)?.toInt() ?? 0;

  int get _pwdCount => _number(_pwdController);

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime date) {
    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) {
      return 'The server took too long to respond. Please try again.';
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  // ==========================================
  // SUCCESS AND ERROR FEEDBACK DIALOG
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
              color: success ? AppColors.primaryGreen : Colors.red,
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ASSESSMENT LOADING MODAL
  // ==========================================

  void _showSavingDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
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
                  'Saving Household Assessment...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please wait while the household assessment '
                  'is saved to the database.',
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

  void _clearFormError() {
    _formError = null;
  }

  // ==========================================
  // LOAD HOUSEHOLDS AND ASSESSMENTS
  // ==========================================

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _assessmentRefreshError = null;
    });

    try {
      final households = await VulnerabilityService.fetchHouseholds();

      final assessments = await VulnerabilityService.fetchAssessments();

      if (!mounted) return;

      setState(() {
        _households = households;
        _assessments = assessments;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loadError = _errorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshAssessments() async {
    if (_isLoading || _isRefreshingAssessments) return;

    setState(() {
      _isRefreshingAssessments = true;
      _assessmentRefreshError = null;
    });

    try {
      // Fetch the latest assessment records from the backend.
      final records = await VulnerabilityService.fetchAssessments();

      if (!mounted) return;

      setState(() {
        _assessments = records;
      });
    } catch (error) {
      if (!mounted) return;

      // Keep the existing records visible and show why refresh failed.
      setState(() {
        _assessmentRefreshError = _errorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingAssessments = false;
        });
      }
    }
  }

  // ==========================================
  // DATE PICKER
  // ==========================================

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _assessmentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.darkText,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selected == null || !mounted) return;

    setState(() {
      _assessmentDate = selected;
      _clearFormError();
    });
  }

  // ==========================================
  // VALIDATION
  // ==========================================

  String? _validateCount(String? value) {
    final number = int.tryParse(value?.trim() ?? '');

    if (number == null) {
      return 'Enter a valid whole number.';
    }

    if (number < 0) {
      return 'Value cannot be negative.';
    }

    return null;
  }

  bool _validatePopulation() {
    if (_selectedHousehold == null) {
      setState(() {
        _formError = 'Please select a registered household.';
      });
      return false;
    }

    if (_ageGroupTotal != _expectedHouseholdSize) {
      setState(() {
        _formError =
            'Age-group total ($_ageGroupTotal) must equal '
            'registered household size ($_expectedHouseholdSize).';
      });
      return false;
    }

    if (_pwdCount > _expectedHouseholdSize) {
      setState(() {
        _formError = 'PWD count cannot exceed household population.';
      });
      return false;
    }

    if (_beneficiaryStatusController.text.trim().isEmpty) {
      setState(() {
        _formError = 'Beneficiary status is required.';
      });
      return false;
    }

    return true;
  }

  // ==========================================
  // SAVE HOUSEHOLD ASSESSMENT
  // ==========================================

  Future<void> _saveAssessment() async {
    if (_isSaving || _isLoading) return;

    FocusScope.of(context).unfocus();

    // Validate required form fields.
    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showFeedbackDialog(
        success: false,
        title: 'Incomplete Assessment',
        message: 'Please complete the required fields highlighted in the form.',
      );
      return;
    }

    // Validate household population.
    if (!_validatePopulation()) {
      await _showFeedbackDialog(
        success: false,
        title: 'Invalid Household Population',
        message: _formError ?? 'Please check the household population.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    // Show the loading modal while saving.
    _showSavingDialog();

    String feedbackTitle = '';
    String feedbackMessage = '';
    bool saveSucceeded = false;

    try {
      final assessmentData = {
        'household_id': _selectedHousehold!['household_id'],

        'assessment_date': _formatDate(_assessmentDate),

        'age_0_5_count': _number(_age0to5Controller),

        'age_6_17_count': _number(_age6to17Controller),

        'age_18_59_count': _number(_age18to59Controller),

        'age_60_plus_count': _number(_age60PlusController),

        'senior_citizens_count': _number(_age60PlusController),

        'pwd_count': _pwdCount,

        'monthly_income_range': _monthlyIncomeRange,

        'employment_status': _employmentStatus,

        'livelihood_type': _livelihoodType,

        'previous_humanitarian_assistance': _previousAssistance,

        'beneficiary_status': _beneficiaryStatusController.text.trim(),

        'disaster_affected': _disasterAffected,

        'housing_damage_level': _disasterAffected
            ? _housingDamageLevel
            : 'None',

        'displaced': _displaced,

        'data_origin': 'synthetic',
      };

      // Save assessment only.
      // Vulnerability classification is handled by its own module.
      await VulnerabilityService.createAssessment(assessmentData);

      if (!mounted) return;

      // Refresh saved assessment records.
      await _refreshAssessments();

      if (!mounted) return;

      saveSucceeded = true;

      feedbackTitle = 'Assessment Saved Successfully';

      feedbackMessage = 'Household assessment has been saved successfully.';
    } catch (error) {
      if (!mounted) return;

      final message = _errorMessage(error);

      setState(() {
        _formError = message;
      });

      feedbackTitle = 'Assessment Not Saved';
      feedbackMessage = message;
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

    // Display the appropriate result after the request finishes.
    await _showFeedbackDialog(
      success: saveSucceeded,
      title: feedbackTitle,
      message: feedbackMessage,
    );
  }

  // ==========================================
  // REUSABLE REFRESH BUTTON
  // ==========================================

  Widget _refreshButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    final isDisabled = onPressed == null || isLoading;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: isDisabled ? null : onPressed,
        borderRadius: BorderRadius.circular(24),

        // This grey pill is visible only while the mouse is over the button.
        hoverColor: const Color(0xFFE5E7EB),
        splashColor: AppColors.lightGreen.withValues(alpha: 0.75),
        highlightColor: AppColors.lightGreen.withValues(alpha: 0.45),

        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
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
                isLoading ? 'Refreshing...' : label,
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

  // ==========================================
  // REUSABLE UI COMPONENTS
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 520;

          final header = Row(
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
                    const SizedBox(height: 3),
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

              // Show beside the heading on desktop.
              if (trailing != null && !isMobile) ...[
                const SizedBox(width: 10),
                trailing,
              ],
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,

              // Move the button below the heading on mobile.
              if (trailing != null && isMobile) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: trailing),
              ],

              const SizedBox(height: 22),

              child,
            ],
          );
        },
      ),
    );
  }

  Widget _fieldGrid(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 650
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: fields.map((field) {
            return SizedBox(width: width, child: field);
          }).toList(),
        );
      },
    );
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      validator: _validateCount,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: const Icon(Icons.numbers_outlined),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.map((option) {
        return DropdownMenuItem<String>(
          value: option,
          child: Text(option, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
      validator:
          validator ??
          (value) => value == null ? 'Please select $label.' : null,
    );
  }

  // ==========================================
  // HOUSEHOLD SELECTOR
  // ==========================================

  // ==========================================
  // SEARCHABLE REGISTERED HOUSEHOLD SELECTOR
  // ==========================================

  Widget _buildHouseholdSelector() {
    final selectedId = (_selectedHousehold?['household_id'] as num?)?.toInt();

    return FormField<int>(
      initialValue: selectedId,

      validator: (value) {
        if (value == null) {
          return 'Please select a registered household.';
        }
        return null;
      },

      builder: (field) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownMenu<int>(
                  key: ValueKey(field.value),

                  width: constraints.maxWidth,

                  // Enable typing and filtering.
                  enableFilter: true,
                  enableSearch: true,
                  requestFocusOnTap: true,

                  // Keep the dropdown scrollable.
                  menuHeight: 300,

                  // Display the currently selected household.
                  initialSelection: field.value,

                  label: const Text('Select Registered Household'),

                  hintText: 'Search by ID, household head, or barangay',

                  leadingIcon: const Icon(Icons.home_work_outlined),

                  trailingIcon: const Icon(Icons.arrow_drop_down),

                  enabled: !_isLoading && !_isSaving && _households.isNotEmpty,

                  // Populate using registered households from FastAPI.
                  dropdownMenuEntries: _households.map((household) {
                    final id = (household['household_id'] as num).toInt();

                    final householdHead = '${household['household_head']}';

                    final barangay = '${household['barangay']}';

                    return DropdownMenuEntry<int>(
                      value: id,
                      label: 'HH-$id | $householdHead | $barangay',
                    );
                  }).toList(),

                  // Update the selected household.
                  onSelected: (id) {
                    if (id == null) return;

                    final household = _households.firstWhere(
                      (item) => (item['household_id'] as num).toInt() == id,
                    );

                    field.didChange(id);

                    setState(() {
                      _selectedHousehold = household;
                      _clearFormError();
                    });
                  },
                ),

                // Preserve form validation feedback.
                if (field.hasError) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // HOUSEHOLD INFORMATION
  // ==========================================

  Widget _buildHouseholdInformation() {
    if (_selectedHousehold == null) {
      return const SizedBox.shrink();
    }

    final household = _selectedHousehold!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.15),
        ),
      ),
      child: Wrap(
        spacing: 30,
        runSpacing: 14,
        children: [
          _infoItem('Household ID', 'HH-${household['household_id']}'),
          _infoItem('Household Head', '${household['household_head']}'),
          _infoItem('Barangay', '${household['barangay']}'),
          _infoItem('Purok', '${household['purok'] ?? 'Not specified'}'),
          _infoItem(
            'Household Population',
            '${household['household_size']} persons',
          ),
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return SizedBox(
      width: 175,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.greyText, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ASSESSMENT DATE
  // ==========================================

  Widget _buildDateSelector() {
    return InkWell(
      onTap: _selectDate,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Assessment Date',
          prefixIcon: Icon(Icons.calendar_month_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(_displayDate(_assessmentDate)),
      ),
    );
  }

  // ==========================================
  // POPULATION SUMMARY
  // ==========================================

  Widget _buildPopulationSummary() {
    final expected = _expectedHouseholdSize;

    final matches = _selectedHousehold != null && _ageGroupTotal == expected;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: matches ? AppColors.lightGreen : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: matches
              ? AppColors.primaryGreen.withValues(alpha: 0.25)
              : AppColors.accentYellow,
        ),
      ),
      child: Row(
        children: [
          Icon(
            matches ? Icons.check_circle_outline : Icons.info_outline,
            color: matches ? AppColors.primaryGreen : const Color(0xFF9A7200),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _selectedHousehold == null
                  ? 'Select a household to view its required population.'
                  : 'Age-group total: $_ageGroupTotal / $expected persons',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ERROR MESSAGE
  // ==========================================

  Widget _buildErrorMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE8B4B0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF9B2525), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ASSESSMENT HISTORY
  // ==========================================

  Widget _buildAssessmentHistory() {
    return _sectionCard(
      title: 'Assessment Records',
      subtitle: 'Saved household assessment records.',
      icon: Icons.history,

      // Refresh button beside Assessment Records.
      trailing: _refreshButton(
        label: 'Refresh records',
        onPressed: (_isLoading || _isRefreshingAssessments)
            ? null
            : _refreshAssessments,
        isLoading: _isRefreshingAssessments,
      ),

      child: Column(
        children: [
          if (_assessmentRefreshError != null)
            _buildErrorMessage(_assessmentRefreshError!),

          if (_assessments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No household assessments have been recorded yet.',
                style: TextStyle(color: AppColors.greyText),
              ),
            )
          else
            ..._assessments.take(10).map((assessment) {
              final id = (assessment['assessment_id'] as num).toInt();

              final householdId = (assessment['household_id'] as num).toInt();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.lightGreen,
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  title: Text(
                    '${assessment['household_head']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    'Assessment #$id • Household #$householdId'
                    '\n${assessment['assessment_date']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.primaryGreen,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ==========================================
  // MAIN SCREEN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(60),
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen heading.
          LayoutBuilder(
            builder: (context, constraints) {
              const heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Household Assessment',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Record household information for vulnerability assessment.',
                    style: TextStyle(fontSize: 12, color: AppColors.greyText),
                  ),
                ],
              );

              final refreshButton = _refreshButton(
                label: 'Refresh assessments',
                onPressed: _loadData,
              );

              // Mobile layout.
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: refreshButton,
                    ),
                  ],
                );
              }

              // Desktop layout.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(child: heading),
                  const SizedBox(width: 12),
                  refreshButton,
                ],
              );
            },
          ),

          const SizedBox(height: 22),

          if (_loadError != null) ...[
            _buildErrorMessage(_loadError!),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ] else ...[
            if (_households.isEmpty)
              _buildErrorMessage(
                'No registered households found. Register a household '
                'before creating an assessment.',
              ),

            // ======================================
            // HOUSEHOLD INFORMATION
            // ======================================
            _sectionCard(
              title: 'Household Information',
              subtitle: 'Select an existing registered household.',
              icon: Icons.home_work_outlined,
              child: Column(
                children: [
                  _buildHouseholdSelector(),
                  if (_selectedHousehold != null) ...[
                    const SizedBox(height: 18),
                    _buildHouseholdInformation(),
                  ],
                  const SizedBox(height: 18),
                  _buildDateSelector(),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ======================================
            // POPULATION AND DEMOGRAPHICS
            // ======================================
            _sectionCard(
              title: 'Household Population and Demographics',
              subtitle:
                  'Enter the number of household members in each age group.',
              icon: Icons.groups_outlined,
              child: Column(
                children: [
                  _fieldGrid([
                    _numberField(
                      label: 'Age 0–5 years',
                      controller: _age0to5Controller,
                    ),
                    _numberField(
                      label: 'Age 6–17 years',
                      controller: _age6to17Controller,
                    ),
                    _numberField(
                      label: 'Age 18–59 years',
                      controller: _age18to59Controller,
                    ),
                    _numberField(
                      label: 'Age 60 years and above',
                      controller: _age60PlusController,
                      helperText: 'Automatically used as senior citizen count.',
                    ),
                    _numberField(
                      label: 'Persons with Disability (PWD)',
                      controller: _pwdController,
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _buildPopulationSummary(),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ======================================
            // SOCIOECONOMIC INFORMATION
            // ======================================
            _sectionCard(
              title: 'Socioeconomic Information',
              subtitle: 'Provide the household income, employment, and livelihood details.',
              icon: Icons.account_balance_wallet_outlined,
              child: _fieldGrid([
                _dropdownField(
                  label: 'Monthly Income Range',
                  value: _monthlyIncomeRange,
                  options: _incomeRanges,
                  onChanged: (value) {
                    setState(() {
                      _monthlyIncomeRange = value;
                      _clearFormError();
                    });
                  },
                ),
                _dropdownField(
                  label: 'Employment Status',
                  value: _employmentStatus,
                  options: _employmentOptions,
                  onChanged: (value) {
                    setState(() {
                      _employmentStatus = value;
                      _clearFormError();
                    });
                  },
                ),
                _dropdownField(
                  label: 'Livelihood Type',
                  value: _livelihoodType,
                  options: _livelihoodOptions,
                  onChanged: (value) {
                    setState(() {
                      _livelihoodType = value;
                      _clearFormError();
                    });
                  },
                ),
                TextFormField(
                  controller: _beneficiaryStatusController,
                  decoration: const InputDecoration(
                    labelText: 'Beneficiary Status',
                    prefixIcon: Icon(Icons.assignment_turned_in_outlined),
                    helperText:
                        'Record status only; this is not an ML input feature.',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Beneficiary status is required.';
                    }
                    if (value.trim().length > 30) {
                      return 'Maximum 30 characters.';
                    }
                    return null;
                  },
                ),
              ]),
            ),

            const SizedBox(height: 18),

            // ======================================
            // ASSISTANCE AND DISASTER INFORMATION
            // ======================================
            _sectionCard(
              title: 'Assistance and Disaster Information',
              subtitle:
                  'Record previous assistance and disaster-related conditions.',
              icon: Icons.health_and_safety_outlined,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primaryGreen,
                    title: const Text(
                      'Previously received humanitarian assistance',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Has this household previously received assistance?',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _previousAssistance,
                    onChanged: (value) {
                      setState(() {
                        _previousAssistance = value;
                        _clearFormError();
                      });
                    },
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppColors.primaryGreen,
                    title: const Text(
                      'Household affected by disaster',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Was the household affected by a disaster?',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _disasterAffected,
                    onChanged: (value) {
                      setState(() {
                        _disasterAffected = value;

                        if (!value) {
                          _housingDamageLevel = 'Minor';
                          _displaced = false;
                        }

                        _clearFormError();
                      });
                    },
                  ),
                  if (_disasterAffected) ...[
                    const SizedBox(height: 12),
                    _dropdownField(
                      label: 'Housing Damage Level',
                      value: _housingDamageLevel,
                      options: _damageOptions,
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          _housingDamageLevel = value;
                          _clearFormError();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.primaryGreen,
                      title: const Text(
                        'Household displaced',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Has the household been displaced?',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _displaced,
                      onChanged: (value) {
                        setState(() {
                          _displaced = value;
                          _clearFormError();
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ======================================
            // DATA ORIGIN NOTICE
            // ======================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppColors.primaryGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Testing mode: This assessment will be marked as '
                      'synthetic data. Replace this source setting only '
                      'when authorized LGU records are available.',
                      style: TextStyle(fontSize: 12, color: AppColors.darkText),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            if (_formError != null) _buildErrorMessage(_formError!),

            // ======================================
            // SAVE BUTTON
            // ======================================
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving || _households.isEmpty
                    ? null
                    : _saveAssessment,
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
                      ? 'Saving Assessment...'
                      : 'Save Household Assessment',
                ),
              ),
            ),

            // Visible pending indicator while the API request is running.
            if (_isSaving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Saving assessment to the database. Please wait...',
                  style: TextStyle(fontSize: 12, color: AppColors.greyText),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Existing assessment records.
            _buildAssessmentHistory(),

            const SizedBox(height: 30),
          ],
        ],
      ),
    );
  }
}
