import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/vulnerability_service.dart';
import '../vulnerability_classification/vulnerability_classification.dart' show apis2022Options;

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
  final _age18to59Controller = TextEditingController(text: '0');
  final _age60PlusController = TextEditingController(text: '0');
  final _apisAge6to11Controller = TextEditingController(text: '0');
  final _apisAge12to17Controller = TextEditingController(text: '0');
  final _apisMonthlyIncomeController = TextEditingController();

  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _assessments = [];

  bool _includeApis2022 = true;
  static const _unclassifiedApisCodes = <String, Set<int>>{
    'apis2022_i2': {8}, 'apis2022_i3': {9}, 'apis2022_i4': {7},
    'apis2022_ws1': {96}, 'apis2022_ws11a': {15, 71, 96},
  };
  final Map<String, int?> _apisAnswers = {};
  bool _apisSingleFamily = false;
  String? _assessmentOrigin;

  Widget _apisQuestion(String name, String label, Map<int, String> options) {
    return DropdownButtonFormField<int>(
      key: ValueKey('$_selectedHousehold-$name'),
      initialValue: _apisAnswers[name],
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: {...options, -1: 'Unknown / other / not applicable'}.entries
          .map((entry) => DropdownMenuItem<int>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          )).toList(),
      onChanged: _isSaving ? null : (value) => setState(() {
        _apisAnswers[name] = value;
        if (name == 'apis2022_g16_nat_disas' && value != 1) {
          _apisAnswers.remove('apis2022_g16a_evac');
          _apisAnswers.remove('apis2022_g16b_recov');
        }
        _clearFormError();
      }),
      validator: (value) {
        if (!_includeApis2022) return null;
        if (value == null || value == -1) return 'A verified answer is required.';
        if (_unclassifiedApisCodes[name]?.contains(value) ?? false) {
          return 'Not supported by the current research model; staff review required.';
        }
        return null;
      },
    );
  }

  Map<String, dynamic>? _selectedHousehold;

  DateTime _assessmentDate = DateTime.now();

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
      _apisAge6to11Controller,
      _apisAge12to17Controller,
      _age18to59Controller,
      _age60PlusController,
    ]) {
      controller.addListener(_onFormChanged);
    }

    _loadData();
  }

  @override
  void dispose() {
    _age0to5Controller.dispose();
    _apisAge6to11Controller.dispose();
    _apisAge12to17Controller.dispose();
    _apisMonthlyIncomeController.dispose();
    _age18to59Controller.dispose();
    _age60PlusController.dispose();

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
      _number(_apisAge6to11Controller) +
      _number(_apisAge12to17Controller) +
      _number(_age18to59Controller) +
      _number(_age60PlusController);

  int get _expectedHouseholdSize =>
      (_selectedHousehold?['household_size'] as num?)?.toInt() ?? 0;


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

    if (_includeApis2022 && !_apisSingleFamily) {
      setState(() => _formError =
          'Confirm one family sharing income before recording APIS 2022 answers.');
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

        'age_6_17_count': _number(_apisAge6to11Controller) + _number(_apisAge12to17Controller),

        'age_18_59_count': _number(_age18to59Controller),

        'age_60_plus_count': _number(_age60PlusController),

        'senior_citizens_count': _number(_age60PlusController),





        'data_origin': _assessmentOrigin,
        'apis_single_family': _includeApis2022 ? _apisSingleFamily : null,
        if (_includeApis2022) ...{
          for (final entry in _apisAnswers.entries)
            entry.key: entry.value == -1 ? null : entry.value,
          'apis2022_g16a_evac': _apisAnswers['apis2022_g16_nat_disas'] == 1
              ? _apisAnswers['apis2022_g16a_evac'] : null,
          'apis2022_g16b_recov': _apisAnswers['apis2022_g16_nat_disas'] == 1
              ? _apisAnswers['apis2022_g16b_recov'] : null,
          'apis2022_mem_age_6_11': _number(_apisAge6to11Controller),
          'apis2022_mem_age_12_17': _number(_apisAge12to17Controller),
          'apis2022_monthly_household_income_php':
              _apisMonthlyIncomeController.text.trim(),
        },
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
                      _apisAnswers.clear();
                      _includeApis2022 = true;
                      _apisSingleFamily = false;
                      _apisAge6to11Controller.text = '0';
                      _apisAge12to17Controller.text = '0';
                      _apisMonthlyIncomeController.clear();
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

  Future<void> _showFinancialHistory(Map<String, dynamic> assessment) async {
    String amount(String key) {
      final value = double.tryParse('${assessment[key]}');
      return value == null ? 'Not recorded' : 'PHP ${value.toStringAsFixed(2)}';
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Family Income and Expenses'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${assessment['household_head']}'),
                const SizedBox(height: 12),
                Text('Reference year: ${assessment['financial_reference_year']}'),
                Text('Average family size: ${assessment['average_family_size']}'),
                Text('Residence classification: ${assessment['financial_residence_classification'] ?? 'Not recorded'}'),
                const SizedBox(height: 12),
                Text('Income: ${amount('annual_family_income')}'),
                Text('Total expenditure: ${amount('annual_family_expenditure')}'),
                Text('Food expenditure: ${amount('annual_food_expenditure')}'),
                Text('Housing and utilities: ${amount('annual_housing_utilities_expenditure')}'),
                Text('Health expenditure: ${amount('annual_health_expenditure')}'),
                Text('Education expenditure: ${amount('annual_education_expenditure')}'),
                Text('Transport expenditure: ${amount('annual_transport_expenditure')}'),
                const SizedBox(height: 12),
                const Text('Annual amounts recorded for staff review.'),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
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
                  onTap: assessment['financial_reference_year'] == null ? null
                      : () => _showFinancialHistory(assessment),
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
                    '\n${assessment['assessment_date']}'
                    '${assessment['financial_reference_year'] == null ? '' : ' • Tap for financial details'}',
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
                    'Record APIS 2022-compatible household inputs for Vulnerability Management.',
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

            // APIS 2022 member record.
            _sectionCard(
              title: 'APIS 2022 • Household Members',
              subtitle:
                  'Counts from the household member roster. All age groups must equal the registered household size.',
              icon: Icons.groups_outlined,
              child: Column(
                children: [
                  _fieldGrid([
                    _numberField(
                      label: 'Age 0–5 years',
                      controller: _age0to5Controller,
                    ),
                    _numberField(
                      label: 'Age 6–11 years (MEM_AGE_6_11)',
                      controller: _apisAge6to11Controller,
                    ),
                    _numberField(
                      label: 'Age 12–17 years (MEM_AGE_12_17)',
                      controller: _apisAge12to17Controller,
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
                  ]),
                  const SizedBox(height: 18),
                  _buildPopulationSummary(),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // APIS 2022 inputs used by the current Random Forest.
            _sectionCard(
              title: 'APIS 2022 • Household Conditions',
              subtitle: 'Record the APIS 2022-equivalent answers. Survey identifiers and research-only fields are not requested.',
              icon: Icons.fact_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Verified APIS 2022 answers available'),
                    subtitle: const Text('Turn off when source answers are not verified; save for staff review. Do not guess codes.'),
                    value: _includeApis2022,
                    onChanged: _isSaving ? null : (value) => setState(() {
                      _includeApis2022 = value;
                      if (!value) _apisAnswers.clear();
                    }),
                  ),
                  if (_includeApis2022) ...[
                    const SizedBox(height: 16),
                    const Text('Housing and electricity',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                    const SizedBox(height: 10),
                    _fieldGrid([
                      _apisQuestion('apis2022_i2', 'Roof material (I2)', apis2022Options['I2']!),
                      _apisQuestion('apis2022_i3', 'Wall material (I3)', apis2022Options['I3']!),
                      _apisQuestion('apis2022_i4', 'Floor material (I4)', apis2022Options['I4']!),
                      _apisQuestion('apis2022_i8', 'Electricity access (I8)', apis2022Options['I8']!),
                    ]),
                    const SizedBox(height: 20),
                    const Text('Water and sanitation',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                    const SizedBox(height: 10),
                    _fieldGrid([
                      _apisQuestion('apis2022_ws1', 'Drinking water source (WS1)', apis2022Options['WS1']!),
                      _apisQuestion('apis2022_ws11a', 'Toilet facility (WS11A)', apis2022Options['WS11A']!),
                    ]),
                    const SizedBox(height: 20),
                    const Text('Disaster preparedness and recovery',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                    const SizedBox(height: 10),
                    _fieldGrid([
                      _apisQuestion('apis2022_g15_kit', 'Emergency preparedness kit (G15)', apis2022Options['G15_KIT']!),
                      _apisQuestion('apis2022_g16_nat_disas', 'Experienced natural disaster (G16)', apis2022Options['G16_NAT_DISAS']!),
                      if (_apisAnswers['apis2022_g16_nat_disas'] == 1) ...[
                        _apisQuestion('apis2022_g16a_evac', 'Evacuation (G16A)', apis2022Options['G16A_EVAC']!),
                        _apisQuestion('apis2022_g16b_recov', 'Recovery (G16B)', apis2022Options['G16B_RECOV']!),
                      ],
                    ]),
                    const SizedBox(height: 20),
                    const Text('Household income',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreen)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _apisMonthlyIncomeController,
                      enabled: !_isSaving,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Verified monthly household income (PHP)',
                        helperText: 'Used as an experimental K5-equivalent; exact APIS K5 meaning requires codebook verification.',
                        helperMaxLines: 2,
                      ),
                      validator: (value) {
                        if (!_includeApis2022) return null;
                        if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch((value ?? '').trim())) {
                          return 'Enter a verified nonnegative monthly amount (up to 2 decimals).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _apisSingleFamily,
                      onChanged: _isSaving ? null : (value) => setState(() => _apisSingleFamily = value ?? false),
                      title: const Text('Income describes one family sharing income and expenses'),
                      subtitle: const Text('Required by the current research prediction contract.'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _assessmentOrigin,
                    validator: (value) => value == null ? 'Select the assessment data source.' : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Assessment data source'),
                    items: const [
                      DropdownMenuItem(value: 'lgu_authorized', child: Text('Verified LGU household assessment')),
                      DropdownMenuItem(value: 'synthetic', child: Text('Practice entry — not verified for decisions')),
                    ],
                    onChanged: _isSaving ? null : (value) => setState(() => _assessmentOrigin = value),
                  ),
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
                      'Check the household information before saving.',
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
