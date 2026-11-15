import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // Format peso amounts while preserving the typed numerical value.
  static final TextInputFormatter _pesoIncomeFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.startsWith('.') ||
        !RegExp(r'^\d{0,12}(\.\d{0,2})?$').hasMatch(raw)) {
      return oldValue;
    }

    final parts = raw.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final formatted = parts.length == 2 ? '$whole.${parts[1]}' : whole;

    var caret = newValue.selection.extentOffset;
    if (caret < 0) caret = newValue.text.length;
    if (caret > newValue.text.length) caret = newValue.text.length;
    final beforeCaret = newValue.text.substring(0, caret).replaceAll(',', '').length;
    var nextCaret = 0;
    var entered = 0;
    while (nextCaret < formatted.length && entered < beforeCaret) {
      if (formatted[nextCaret] != ',') entered++;
      nextCaret++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: nextCaret),
    );
  });

  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _assessments = [];

  bool _includeApis2022 = true;
  static const _unclassifiedApisCodes = <String, Set<int>>{
    'apis2022_i2': {8}, 'apis2022_i3': {9}, 'apis2022_i4': {7},
    'apis2022_ws1': {96}, 'apis2022_ws11a': {15, 71, 96},
  };
  final Map<String, int?> _apisAnswers = {};
  final Map<String, dynamic> _expandedAnswers = {};
  List<Map<String, dynamic>> _expandedCatalog = [];
  List<Map<String, dynamic>> _socialCatalog = [];
  final Map<String, dynamic> _socialAnswers = {};
  final Map<String, List<int>> _programSelections = {};
  String? _expandedLoadError;
  int? _editingAssessmentId;
  int _editorVersion = 0;
  final GlobalKey _editStartKey = GlobalKey();

  Future<void> _loadExpandedCatalog() async {
    try {
      final result = await VulnerabilityService.fetchApis2022FeatureCatalog();
      if (!mounted) return;
      setState(() {
        _expandedCatalog = (result['assessment'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
        _socialCatalog = (result['social'] as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();
        _expandedLoadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _expandedLoadError = error.toString());
    }
  }

  Widget _expandedField(Map<String, dynamic> spec) {
    final name = spec['name'] as String;
    final label = spec['label'] as String;
    if (spec['kind'] == 'code') {
      return DropdownButtonFormField<String>(
        key: ValueKey('$_editorVersion-${_selectedHousehold?['household_id']}-$name'),
        initialValue: _expandedAnswers[name]?.toString() ?? '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(value: '', child: Text('Select answer')),
          DropdownMenuItem(value: '1', child: Text('Yes')),
          DropdownMenuItem(value: '2', child: Text('No')),
        ],
        onChanged: _isSaving ? null : (value) => setState(() {
          if (value == null || value.isEmpty) {
            _expandedAnswers.remove(name);
          } else {
            _expandedAnswers[name] = value;
          }
          _clearFormError();
        }),
      );
    }
    return TextFormField(
      key: ValueKey('$_editorVersion-${_selectedHousehold?['household_id']}-$name'),
      initialValue: _expandedAnswers[name]?.toString() ?? '',
      enabled: !_isSaving,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Number of bedrooms',
        helperText: 'Enter the confirmed number. Leave blank if unknown.',
      ),
      validator: (value) {
        if ((value ?? '').trim().isEmpty) return null;
        final count = int.tryParse(value!.trim());
        if (count == null || count < 0 || count > 30) {
          return 'Enter a whole number from 0 to 30.';
        }
        return null;
      },
      onChanged: (value) {
        if (value.trim().isEmpty) {
          _expandedAnswers.remove(name);
        } else {
          _expandedAnswers[name] = int.tryParse(value.trim()) ?? value.trim();
        }
      },
    );
  }

  Widget _bedroomInput() {
    final matches = _expandedCatalog.where((spec) => spec['name'] == 'I7');
    if (matches.isEmpty) return const Text('Loading bedroom question...');
    return _expandedField(matches.first);
  }

  List<Widget> _assetCards() {
    if (_expandedLoadError != null) {
      return [Text('Household assets unavailable: $_expandedLoadError',
          style: const TextStyle(color: Colors.red))];
    }
    if (_expandedCatalog.isEmpty) {
      return [const Text('Loading household asset questions...')];
    }
    const headings = <String, IconData>{
      'Transportation and livelihood assets': Icons.directions_car_outlined,
      'Home appliances and equipment': Icons.kitchen_outlined,
      'Communication and technology': Icons.devices_outlined,
    };
    return headings.entries.map((heading) {
      final fields = _expandedCatalog
          .where((spec) => spec['section'] == heading.key)
          .map(_expandedField).toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: _sectionCard(
          title: heading.key,
          subtitle: 'Does the household currently own or subscribe to each item?',
          icon: heading.value,
          child: _fieldGrid(fields),
        ),
      );
    }).toList();
  }
  bool _apisSingleFamily = false;
  String? _assessmentOrigin;

  Widget _apisQuestion(String name, String label, Map<int, String> options) {
    return DropdownButtonFormField<int>(
      key: ValueKey('$_editorVersion-${_selectedHousehold?['household_id']}-$name'),
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
    _loadExpandedCatalog();
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

    // Feeding responses use rolling six-month periods relative to the
    // assessment date. Changing that date requires staff to verify again.
    final feedingPeriodsChanged = selected.year != _assessmentDate.year ||
        selected.month != _assessmentDate.month ||
        selected.day != _assessmentDate.day;
    setState(() {
      if (feedingPeriodsChanged) {
        _programSelections.remove('G11_CODE1_COUNT');
        _socialAnswers.remove('G11_CODE1_COUNT');
      }
      _assessmentDate = selected;
      _clearFormError();
    });
    if (feedingPeriodsChanged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Assessment date changed. Please verify government feeding support '
          'for the new assessment date.',
        )),
      );
    }
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

    if (_selectedHousehold?['members_complete'] != true) {
      setState(() {
        _formError =
            'Complete the household member names in Household Registration '
            'before saving the assessment.';
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

    if (_includeApis2022 && (_expandedCatalog.isEmpty || _socialCatalog.length != 9)) {
      await _showFeedbackDialog(
        success: false,
        title: 'Assessment Questions Not Loaded',
        message: _expandedLoadError ?? 'Check the FastAPI connection and reload the assessment.',
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
        'apis2022_extended_answers': _includeApis2022
            ? Map<String, dynamic>.from(_expandedAnswers)
            : <String, dynamic>{},
        'apis2022_social_answers': _includeApis2022
            ? Map<String, dynamic>.from(_socialAnswers)
            : <String, dynamic>{},
        'apis2022_program_selections': _includeApis2022
            ? <String, List<int>>{
                for (final entry in _programSelections.entries)
                  entry.key: List<int>.from(entry.value),
              }
            : <String, List<int>>{},
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
              _apisMonthlyIncomeController.text.trim().replaceAll(',', ''),
        },
      };

      // Save assessment only.
      // Vulnerability classification is handled by its own module.
      if (_editingAssessmentId == null) {
        await VulnerabilityService.createAssessment(assessmentData);
      } else {
        await VulnerabilityService.updateAssessment(
          _editingAssessmentId!, assessmentData,
        );
      }

      if (!mounted) return;

      // Refresh saved assessment records.
      await _refreshAssessments();

      if (!mounted) return;

      saveSucceeded = true;
      final wasEditing = _editingAssessmentId != null;
      feedbackTitle = wasEditing
          ? 'Assessment Updated Successfully'
          : 'Assessment Saved Successfully';
      feedbackMessage = wasEditing
          ? 'The household assessment has been updated.'
          : 'Household assessment has been saved successfully.';
      if (wasEditing) _cancelEditAssessment();
    } catch (error) {
      if (!mounted) return;

      final message = _errorMessage(error);

      setState(() {
        _formError = message;
      });

      feedbackTitle = _editingAssessmentId == null
          ? 'Assessment Not Saved'
          : 'Assessment Not Updated';
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
      key: ValueKey('household-$_editorVersion'),
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

                  enabled: !_isLoading && !_isSaving && _editingAssessmentId == null && _households.isNotEmpty,

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
                      _expandedAnswers.clear();
                      _socialAnswers.clear();
                      _programSelections.clear();
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

  // Open a saved assessment in the full form. A classified assessment is
  // immutable, because changing its evidence would invalidate the prediction.
  Future<void> _editSavedAssessment(Map<String, dynamic> assessment) async {
    if (assessment['has_classification'] == true) {
      await _showFeedbackDialog(
        success: false,
        title: 'Assessment Locked',
        message: 'A classification has already been generated. '
            'Create a new assessment to record updated household information.',
      );
      return;
    }
    if (_expandedCatalog.isEmpty || _socialCatalog.length != 9) {
      await _showFeedbackDialog(
        success: false,
        title: 'Assessment Questions Unavailable',
        message: 'Refresh the page before editing this assessment.',
      );
      return;
    }
    final householdId = (assessment['household_id'] as num).toInt();
    final matching = _households.where(
      (household) => (household['household_id'] as num).toInt() == householdId,
    );
    if (matching.isEmpty) {
      await _showFeedbackDialog(
        success: false,
        title: 'Household Not Found',
        message: 'Refresh Household Registration before editing this assessment.',
      );
      return;
    }
    int count(String key) => (assessment[key] as num?)?.toInt() ?? 0;
    String incomeText() {
      final raw = assessment['apis2022_monthly_household_income_php'];
      if (raw == null) return '';
      final text = raw.toString();
      final parts = text.split('.');
      final whole = parts.first.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',',
      );
      return parts.length == 2 ? '$whole.${parts.last}' : whole;
    }
    setState(() {
      _editingAssessmentId = (assessment['assessment_id'] as num).toInt();
      _selectedHousehold = matching.first;
      _assessmentDate = DateTime.parse(assessment['assessment_date'].toString());
      _age0to5Controller.text = count('age_0_5_count').toString();
      _apisAge6to11Controller.text = count('apis2022_mem_age_6_11').toString();
      _apisAge12to17Controller.text = count('apis2022_mem_age_12_17').toString();
      _age18to59Controller.text = count('age_18_59_count').toString();
      _age60PlusController.text = count('age_60_plus_count').toString();
      _apisMonthlyIncomeController.text = incomeText();
      _apisSingleFamily = assessment['apis_single_family'] == true;
      _assessmentOrigin = assessment['data_origin']?.toString();
      _includeApis2022 = true;
      _apisAnswers.clear();
      for (final key in const [
        'apis2022_i2', 'apis2022_i3', 'apis2022_i4', 'apis2022_i8',
        'apis2022_ws1', 'apis2022_ws11a', 'apis2022_g15_kit',
        'apis2022_g16_nat_disas', 'apis2022_g16a_evac', 'apis2022_g16b_recov',
      ]) {
        if (assessment[key] is num) {
          _apisAnswers[key] = (assessment[key] as num).toInt();
        }
      }
      _expandedAnswers
        ..clear()
        ..addAll(Map<String, dynamic>.from(
          assessment['apis2022_extended_answers'] as Map? ?? {},
        ));
      _socialAnswers
        ..clear()
        ..addAll(Map<String, dynamic>.from(
          assessment['apis2022_social_answers'] as Map? ?? {},
        ));
      _programSelections.clear();
      final rawSelections = assessment['apis2022_program_selections'];
      if (rawSelections is Map) {
        for (final entry in rawSelections.entries) {
          if (entry.value is List) {
            _programSelections[entry.key.toString()] = (entry.value as List)
                .whereType<num>()
                .map((code) => code.toInt())
                .toList();
          }
        }
      }
      _formError = null;
      _editorVersion++;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editStartKey.currentContext != null) {
        Scrollable.ensureVisible(
          _editStartKey.currentContext!,
          duration: const Duration(milliseconds: 350),
          alignment: 0.03,
        );
      }
    });
  }

  void _cancelEditAssessment() {
    setState(() {
      _editingAssessmentId = null;
      _selectedHousehold = null;
      _assessmentDate = DateTime.now();
      _age0to5Controller.text = '0';
      _apisAge6to11Controller.text = '0';
      _apisAge12to17Controller.text = '0';
      _age18to59Controller.text = '0';
      _age60PlusController.text = '0';
      _apisMonthlyIncomeController.clear();
      _apisAnswers.clear();
      _expandedAnswers.clear();
      _socialAnswers.clear();
      _programSelections.clear();
      _apisSingleFamily = false;
      _assessmentOrigin = null;
      _formError = null;
      _editorVersion++;
    });
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
                  trailing: assessment['has_classification'] == true
                      ? const Tooltip(
                          message: 'Classified assessments cannot be edited. '
                              'Create a new assessment for updated information.',
                          child: Chip(
                            avatar: Icon(Icons.lock_outline, size: 16),
                            label: Text('Locked'),
                          ),
                        )
                      : TextButton.icon(
                          onPressed: _isSaving ? null : () => _editSavedAssessment(assessment),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Edit Assessment'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryGreen,
                          ),
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
          // Scroll target when editing an existing assessment.
          SizedBox(key: _editStartKey, height: 1),
          if (_editingAssessmentId != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.edit_note, color: AppColors.primaryGreen),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Editing Assessment #$_editingAssessmentId — update the full '
                  'questionnaire below. Once classified, the record is locked.',
                )),
                TextButton(onPressed: _isSaving ? null : _cancelEditAssessment,
                  child: const Text('Cancel Edit')),
              ]),
            ),
            const SizedBox(height: 14),
          ],
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
              title: 'Household Members',
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
                      label: 'Age 6–11 years',
                      controller: _apisAge6to11Controller,
                    ),
                    _numberField(
                      label: 'Age 12–17 years',
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

            _sectionCard(
              title: 'Housing structure and electricity',
              subtitle: 'Record the household’s observed living conditions.',
              icon: Icons.home_outlined,
              child: _fieldGrid([
                _apisQuestion('apis2022_i2', 'Roof material', apis2022Options['I2']!),
                _apisQuestion('apis2022_i3', 'Wall material', apis2022Options['I3']!),
                _apisQuestion('apis2022_i4', 'Floor material', apis2022Options['I4']!),
                _apisQuestion('apis2022_i8', 'Electricity access', apis2022Options['I8']!),
                _bedroomInput(),
              ]),
            ),
            const SizedBox(height: 18),
            ..._assetCards(),
            _sectionCard(
              title: 'Water and sanitation',
              subtitle: 'Main drinking-water source and toilet facility.',
              icon: Icons.water_drop_outlined,
              child: _fieldGrid([
                _apisQuestion('apis2022_ws1', 'Drinking water source', apis2022Options['WS1']!),
                _apisQuestion('apis2022_ws11a', 'Toilet facility', apis2022Options['WS11A']!),
              ]),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Disaster preparedness and recovery',
              subtitle: 'Record disaster experience and any applicable follow-up answers.',
              icon: Icons.health_and_safety_outlined,
              child: _fieldGrid([
                _apisQuestion('apis2022_g15_kit', 'Does the household have an emergency go bag?', apis2022Options['G15_KIT']!),
                _apisQuestion('apis2022_g16_nat_disas', 'Has the household experienced a natural disaster?', apis2022Options['G16_NAT_DISAS']!),
                if (_apisAnswers['apis2022_g16_nat_disas'] == 1) ...[
                  _apisQuestion('apis2022_g16a_evac', 'Was the household displaced or evacuated?', apis2022Options['G16A_EVAC']!),
                  _apisQuestion('apis2022_g16b_recov', 'Has the household recovered from the disaster?', apis2022Options['G16B_RECOV']!),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Household income',
              subtitle: 'Use the verified monthly family income for this assessment.',
              icon: Icons.payments_outlined,
              child: Column(
                children: [
                  TextFormField(
                    controller: _apisMonthlyIncomeController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_pesoIncomeFormatter],
                    decoration: const InputDecoration(
                      labelText: 'Average monthly family income',
                      hintText: 'e.g., 15,000.00',
                      prefixText: '₱ ',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      helperText: 'Enter the verified monthly family income in pesos.',
                    ),
                    validator: (value) {
                      final amount = (value ?? '').trim().replaceAll(',', '');
                      if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(amount)) {
                        return 'Enter a verified amount with up to two decimal places.';
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
                    title: const Text('The income covers this one family'),
                    subtitle: const Text('Confirm the same family is represented by the member counts.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Health coverage and local welfare',
              subtitle: 'Membership and services used by household members.',
              icon: Icons.health_and_safety_outlined,
              child: _socialCatalog.length != 9
                  ? Text(_expandedLoadError ?? 'Loading social-protection questions...')
                  : _SocialProtectionFields(
                      specs: _socialCatalog,
                      answers: _socialAnswers,
                      enabled: !_isSaving,
                      onChanged: (updated) => setState(() {
                        _socialAnswers..clear()..addAll(updated);
                        _clearFormError();
                      }),
                    ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Program participation',
              subtitle: 'Choose applicable programs in separate checklists.',
              icon: Icons.volunteer_activism_outlined,
              child: _socialCatalog.length != 9
                  ? Text(_expandedLoadError ?? 'Loading program questions...')
                  : _ProgramParticipationFields(
                      specs: _socialCatalog,
                      answers: _socialAnswers,
                      selections: _programSelections,
                      enabled: !_isSaving,
                      onChanged: (answers, selections) => setState(() {
                        _socialAnswers..clear()..addAll(answers);
                        _programSelections..clear()..addAll(selections);
                        _clearFormError();
                      }),
                    ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Assessment information source',
              subtitle: 'Specify how the answers were obtained.',
              icon: Icons.verified_user_outlined,
              child: DropdownButtonFormField<String>(
                key: ValueKey('origin-$_editorVersion'),
                initialValue: _assessmentOrigin,
                validator: (value) => value == null ? 'Select the assessment source.' : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Information source'),
                items: const [
                  DropdownMenuItem(value: 'lgu_authorized', child: Text('Verified household assessment')),
                  DropdownMenuItem(value: 'synthetic', child: Text('Practice entry (not for actual aid decisions)')),
                ],
                onChanged: _isSaving ? null : (value) => setState(() => _assessmentOrigin = value),
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
                      : (_editingAssessmentId == null
                          ? 'Save Household Assessment'
                          : 'Update Household Assessment'),
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

// Social Protection belongs to Household Assessment. The trained Random
// Forest only uses the nine saved responses; detailed program choices are
// stored separately so staff can reopen the form without losing checkmarks.
class _SocialProtectionFields extends StatelessWidget {
  const _SocialProtectionFields({
    required this.specs,
    required this.answers,
    required this.enabled,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> specs;
  final Map<String, dynamic> answers;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onChanged;

  bool _hasField(String key) => specs.any((spec) => spec['name'] == key);

  void _set(String key, String? value) {
    final next = Map<String, dynamic>.from(answers);
    if (value == null || value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    if (key == 'G13_PHEALTH' && value != '1' && value != '2') {
      next.remove('G13A_ASSISTANCE');
    }
    if (key == 'G14_AWARE' && value != '1') {
      next.remove('G14A_CONSULT');
    }
    onChanged(next);
  }

  Widget _field(String key, String label, {bool philHealth = false}) {
    if (!_hasField(key)) return const SizedBox.shrink();

    // Keep all four questions visible. A follow-up is disabled, not hidden,
    // when the corresponding survey skip condition applies.
    final coverage = answers['G13_PHEALTH']?.toString();
    final aware = answers['G14_AWARE']?.toString();
    final isBenefit = key == 'G13A_ASSISTANCE';
    final isWelfareUse = key == 'G14A_CONSULT';
    final canAnswer = (!isBenefit || coverage == '1' || coverage == '2') &&
        (!isWelfareUse || aware == '1');

    String? helper;
    if (isBenefit && !canAnswer) {
      helper = coverage == '3'
          ? 'Not applicable — household has no PhilHealth coverage.'
          : 'Select the PhilHealth coverage answer first.';
    } else if (isWelfareUse && !canAnswer) {
      helper = aware == '2'
          ? 'Not applicable — household is not aware of these services.'
          : 'Select the local welfare awareness answer first.';
    }

    const yesNo = {'1': 'Yes', '2': 'No'};
    const coverageOptions = {
      '1': 'Yes — paying member',
      '2': 'Yes — non-paying member',
      '3': 'No',
    };
    final options = philHealth ? coverageOptions : yesNo;
    final current = answers[key]?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('social-$key-$current'),
        initialValue: options.containsKey(current) ? current : '',
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
        ),
        items: [
          const DropdownMenuItem<String>(
            value: '', child: Text('Select answer'),
          ),
          ...options.entries.map((option) => DropdownMenuItem<String>(
            value: option.key,
            child: Text(option.value, overflow: TextOverflow.ellipsis),
          )),
        ],
        onChanged: enabled && canAnswer ? (value) => _set(key, value) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Answer using verified household information. Follow-up questions remain visible and become available when applicable.',
          style: TextStyle(fontSize: 12, color: AppColors.greyText),
        ),
        const SizedBox(height: 18),
        const Text('PhilHealth coverage',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _field('G13_PHEALTH', 'Is the family covered by PhilHealth?',
            philHealth: true),
        _field('G13A_ASSISTANCE', 'Has the family availed of PhilHealth benefits?'),
        const SizedBox(height: 8),
        const Divider(height: 20),
        const SizedBox(height: 8),
        const Text('Local welfare services',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _field('G14_AWARE', 'Is the family aware of local welfare services?'),
        _field('G14A_CONSULT', 'Has the family consulted or used local welfare services?'),
      ],
    );
  }
}

// Five separate checklists. A selected item corresponds to an original
// survey code-1 response. Counts are never typed or guessed by staff.
class _ProgramParticipationFields extends StatelessWidget {
  const _ProgramParticipationFields({
    required this.specs,
    required this.answers,
    required this.selections,
    required this.enabled,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> specs;
  final Map<String, dynamic> answers;
  final Map<String, List<int>> selections;
  final bool enabled;
  final void Function(Map<String, dynamic>, Map<String, List<int>>) onChanged;

  // Names and exact order are from apis_2022_metadata(dictionary).xlsx,
  // sheet apis_2022_valueset: G1CODE, G5CODE, G9CODE, G11CODE and H1CODE.
  static const _categories = <String, List<String>>{
    'G1_CODE1_COUNT': [
      'Social Security System (SSS)',
      'Government Service Insurance System (GSIS)',
      'Overseas Workers Welfare Administration (OWWA)',
      'Health Maintenance Organization (HMO), excluding PhilHealth',
      'Life insurance',
    ],
    'G5_CODE1_COUNT': [
      'Regular 4Ps',
      'Modified 4Ps',
      'Social pension for indigent senior citizens',
      'Assistance from a Malasakit Center',
      'Student financial assistance',
      'Assistance to Individuals in Crisis Situation (AICS)',
      'Balik Probinsya Program',
      'Emergency shelter assistance',
    ],
    'G9_CODE1_COUNT': [
      'Microenterprise development assistance',
      'Employment facilitation assistance',
      'Skills training',
      'DOLE integrated livelihood assistance (Kabuhayan Program)',
    ],
    // Two rolling periods relative to the date of the assessment.
    'G11_CODE1_COUNT': [
      'Within the past 6 months',
      'During the preceding 6 months',
    ],
    'H1_CODE1_COUNT': [
      'Police, barangay or other law-enforcement assistance',
      'Public attorney or prosecutor office assistance',
      'Court services',
      'Public school enrolment or other education services',
      'Government medical check-up, hospital care or vaccination',
      'SSS or other government institution loans or benefits',
      'Government employment or livelihood assistance',
      'Civil registry documents (birth, marriage, CENOMAR, etc.)',
      'Passport, DFA document authentication or government ID',
      'Land title or property document registration',
      'Government permits and clearances',
      'Government taxes, cedula or similar payments',
    ],
  };

  static const _titles = <String, String>{
    'G1_CODE1_COUNT': 'Social insurance membership',
    'G5_CODE1_COUNT': 'Social assistance received',
    'G9_CODE1_COUNT': 'Employment and livelihood support',
    'G11_CODE1_COUNT': 'Government feeding support',
    'H1_CODE1_COUNT': 'Government services accessed',
  };

  static const _questions = <String, String>{
    'G1_CODE1_COUNT':
        'Is any household member a member, beneficiary or dependent of these insurance programs?',
    'G5_CODE1_COUNT':
        'Has any household member received support from any of these programs?',
    'G9_CODE1_COUNT':
        'Has any household member received any of these employment or livelihood services?',
    'G11_CODE1_COUNT':
        'Has anyone in the household received support from a government feeding program during either of these periods?',
    'H1_CODE1_COUNT':
        'Did anyone in the household visit a government agency for any of these purposes?',
  };

  // The display uses rolling six-month windows rather than calendar
  // half-years. Codes 1 and 2 still map to the two checked periods.
  List<String> _feedingPeriodLabels() => const <String>[
    'Within the past 6 months',
    'During the preceding 6 months',
  ];

  void _apply(String key, List<int> selected) {
    final nextAnswers = Map<String, dynamic>.from(answers);
    final nextSelections = <String, List<int>>{
      for (final entry in selections.entries)
        entry.key: List<int>.from(entry.value),
    };
    if (selected.contains(-1)) {
      // Not verified is different from a confirmed count of zero.
      nextAnswers.remove(key);
      nextSelections.remove(key);
    } else {
      nextAnswers[key] = selected.length;
      nextSelections[key] = selected;
    }
    onChanged(nextAnswers, nextSelections);
  }

  Future<void> _openChecklist(BuildContext context, String key) async {
    if (!enabled) return;
    final available = key == 'G11_CODE1_COUNT'
        ? _feedingPeriodLabels()
        : _categories[key]!;
    final checked = <int>{...?selections[key]};
    final result = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: Text(_titles[key]!),
          content: SizedBox(
            width: 530,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.60,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(_questions[key]!,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  if (key == 'G11_CODE1_COUNT')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        'Use the assessment date as the reference. Tick each '
                        'period when government feeding-program support was '
                        'confirmed. Do not count ordinary disaster-relief food packs.',
                        style: const TextStyle(
                          fontSize: 11, color: AppColors.greyText,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  ...List.generate(available.length, (index) {
                    final code = index + 1;
                    return CheckboxListTile(
                      key: ValueKey('choice-$key-$code'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(available[index],
                          style: const TextStyle(fontSize: 13)),
                      value: checked.contains(code),
                      onChanged: (selected) => setModalState(() {
                        if (selected == true) {
                          checked.add(code);
                        } else {
                          checked.remove(code);
                        }
                      }),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text('${checked.length} of ${available.length} selected',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'If none apply, leave every box unchecked and save. '
                    'If you have not verified the answers, choose Not verified.',
                    style: TextStyle(fontSize: 11, color: AppColors.greyText),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(<int>[-1]),
              child: const Text('Not verified'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final sorted = checked.toList()..sort();
                Navigator.of(dialogContext).pop(sorted);
              },
              child: const Text('Save choices'),
            ),
          ],
        ),
      ),
    );
    if (result != null) _apply(key, result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Open a group and tick every applicable program or service. '
          'AidTrack counts the checked categories automatically.',
          style: TextStyle(fontSize: 12, color: AppColors.greyText),
        ),
        const SizedBox(height: 14),
        for (final entry in _categories.entries) ...[
          if (specs.any((spec) => spec['name'] == entry.key))
            _groupRow(context, entry.key, entry.value.length),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _groupRow(BuildContext context, String key, int maximum) {
    final count = answers[key] is num
        ? (answers[key] as num).toInt()
        : int.tryParse(answers[key]?.toString() ?? '');
    final detailed = selections.containsKey(key);
    final status = count == null
        ? 'Not verified'
        : detailed
            ? '$count of $maximum selected'
            : 'Saved total: $count — choices not recorded';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 190, maxWidth: 470),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titles[key]!,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 4),
                Text(status,
                    style: TextStyle(
                      fontSize: 12,
                      color: count == null
                          ? AppColors.greyText : AppColors.primaryGreen,
                    )),
                if (key == 'G11_CODE1_COUNT') ...[
                  const SizedBox(height: 3),
                  Text(
                    'Past 12 months · two 6-month periods',
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.greyText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: enabled ? () => _openChecklist(context, key) : null,
            icon: const Icon(Icons.checklist_rtl, size: 17),
            label: Text(key == 'G11_CODE1_COUNT'
                ? (detailed ? 'Edit periods' : 'Select periods')
                : (detailed ? 'Edit choices' : 'Select programs')),
          ),
        ],
      ),
    );
  }
}
