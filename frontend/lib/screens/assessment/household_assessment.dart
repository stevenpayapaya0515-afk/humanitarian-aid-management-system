import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../services/vulnerability_service.dart';
import '../vulnerability_classification/vulnerability_classification.dart'
    show apis2022Options;

// Matches backend/schemas/assessments.py (46 model inputs).
// family_size comes from Registration; monthly_income_per_capita is DB-generated.
class HouseholdAssessmentScreen extends StatefulWidget {
  const HouseholdAssessmentScreen({super.key});

  @override
  State<HouseholdAssessmentScreen> createState() =>
      _HouseholdAssessmentScreenState();
}

class _HouseholdAssessmentScreenState extends State<HouseholdAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _incomeController = TextEditingController();
  final Map<String, TextEditingController> _numbers = {};
  final Map<String, int?> _answers = {};
  final Map<String, Map<String, dynamic>> _catalog = {};
  final Map<String, List<int?>> _programSelections = {};

  static const _ageFields = <String>[
    'members_age_0_5',
    'members_age_6_11',
    'members_age_12_17',
    'members_age_60_plus',
  ];
  static const _housingFields = <String>[
    'roof_material',
    'outer_wall_material',
    'floor_material',
    'electricity_available',
    'bedroom_count',
  ];
  static const _waterFields = <String>[
    'drinking_water_source',
    'toilet_facility',
  ];
  static const _disasterFields = <String>[
    'disaster_preparedness_kit',
    'experienced_natural_disaster',
    'disaster_evacuated_or_displaced',
    'recovered_from_disaster',
  ];
  static const _assetFields = <String>[
    'owns_car_jeep_van',
    'owns_electric_jeep',
    'owns_motorcycle_tricycle',
    'owns_electric_tricycle',
    'owns_motorized_boat',
    'owns_tractor',
    'owns_washing_machine',
    'owns_stove_with_oven_or_gas_range',
    'owns_induction_stove',
    'owns_refrigerator_freezer',
    'owns_personal_computer',
    'owns_air_conditioner',
    'owns_basic_cellphone',
    'owns_smartphone',
    'owns_microwave_or_oven_toaster',
    'owns_landline_or_wireless_telephone',
    'owns_videoke_magic_sing',
    'owns_television',
    'owns_radio',
    'owns_draft_animals',
  ];
  static const _subscriptionFields = <String>[
    'has_cable_subscription',
    'has_broadband_internet_subscription',
    'has_video_streaming_subscription',
  ];
  static const _philHealthFields = <String>[
    'philhealth_membership_status',
    'received_philhealth_benefits',
  ];

  // G1, G5, G9 and H1 of the official 2022 APIS questionnaire.
  // Order is preserved; one Yes contributes one to the model input count.
  static const _programChoices = <String, List<String>>{
    'social_insurance_program_count': [
      'Social Security System (SSS)',
      'Government Service Insurance System (GSIS)',
      'Overseas Workers Welfare Administration (OWWA)',
      'Health or medical insurance other than PhilHealth',
      'Life insurance or pre-need insurance',
    ],
    'social_assistance_program_count': [
      'Regular Pantawid Pamilyang Pilipino Program (4Ps)',
      'Modified Pantawid Pamilyang Pilipino Program (4Ps)',
      'Indigent Senior Citizens Social Pension (SocPen)',
      'Malasakit Center assistance',
      'Student Financial Assistance (StuFAP), excluding UAQTE',
      'Assistance to Individuals in Crisis Situation (AICS)',
      'Balik Probinsya Program',
      'Emergency Shelter Assistance (ESA)',
    ],
    'labor_market_program_count': [
      'Micro Enterprise Development Track',
      'Employment Facilitation Track',
      'TESDA skills training',
      'DOLE Integrated Livelihood / Kabuhayan Program',
    ],
    'government_services_accessed_count': [
      'Police, barangay, or other law-enforcement assistance',
      'Public attorney or fiscal office services',
      'Court-related services',
      'Public education and scholarships',
      'Public healthcare services',
      'Government benefits or loans (SSS, GSIS, Pag-IBIG, PhilHealth)',
      'Employment, livelihood, or poverty assistance',
      'Civil registry certificates',
      'Passports, DFA documents, or government IDs',
      'Land titles or property registration',
      'Government permits, licenses, or clearances',
      'Taxes, cedula, or other government duties',
    ],
  };

  static const _programTitles = <String, String>{
    'social_insurance_program_count': 'Social Insurance',
    'social_assistance_program_count': 'Social Assistance',
    'labor_market_program_count': 'Employment and Livelihood Programs',
    'government_services_accessed_count': 'Government Services',
  };

  static const _programPrompts = <String, String>{
    'social_insurance_program_count':
        'Is any family member a member, dependent, or beneficiary?',
    'social_assistance_program_count':
        'During the past 6 months, did anyone receive this assistance?',
    'labor_market_program_count':
        'During the past 6 months, did anyone benefit from these programs?',
    'government_services_accessed_count':
        'During the past 12 months, did anyone access these services?',
  };
  static const _numericRanges = <String, int>{
    'members_age_0_5': 200,
    'members_age_6_11': 200,
    'members_age_12_17': 200,
    'members_age_60_plus': 200,
    'bedroom_count': 100,
    'social_insurance_program_count': 5,
    'social_assistance_program_count': 8,
    'labor_market_program_count': 4,
    'government_services_accessed_count': 12,
  };
  static const _surveyChoices = <String, String>{
    'roof_material': 'I2',
    'outer_wall_material': 'I3',
    'floor_material': 'I4',
    'electricity_available': 'I8',
    'drinking_water_source': 'WS1',
    'toilet_facility': 'WS11A',
    'disaster_preparedness_kit': 'G15_KIT',
    'experienced_natural_disaster': 'G16_NAT_DISAS',
    'disaster_evacuated_or_displaced': 'G16A_EVAC',
    'recovered_from_disaster': 'G16B_RECOV',
  };

  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _assessments = [];
  Map<String, dynamic>? _selectedHousehold;
  DateTime _assessmentDate = DateTime.now();
  String _dataOrigin = 'synthetic';
  bool _confirmedSingleFamily = false;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  int? _editingId;
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    for (final field in _numericRanges.keys) {
      _numbers[field] = TextEditingController();
    }
    _resetProgramSelections();
    _load();
  }

  @override
  void dispose() {
    _incomeController.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? get _familySize =>
      (_selectedHousehold?['household_size'] as num?)?.toInt();

  String _dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _errorText(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  int? _number(String name) {
    final raw = _numbers[name]?.text.trim() ?? '';
    return raw.isEmpty ? null : int.tryParse(raw);
  }

  double? get _income {
    final raw = _incomeController.text.trim().replaceAll(',', '');
    return raw.isEmpty ? null : double.tryParse(raw);
  }

  double? get _perCapita {
    final size = _familySize;
    final income = _income;
    if (size == null || size <= 0 || income == null) return null;
    return income / size;
  }

  bool get _allAgeGroupsComplete =>
      _ageFields.every((name) => _number(name) != null);

  int get _ageSubtotal =>
      _ageFields.fold(0, (total, name) => total + (_number(name) ?? 0));

  int? get _workingAgeCount {
    final size = _familySize;
    if (size == null || size < 1 || !_allAgeGroupsComplete) {
      return null;
    }
    final remaining = size - _ageSubtotal;
    return remaining >= 0 ? remaining : null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        VulnerabilityService.fetchHouseholds(),
        VulnerabilityService.fetchAssessments(),
        VulnerabilityService.fetchApis2022FeatureCatalog(),
      ]);
      final catalogResponse = results[2] as Map<String, dynamic>;
      final features = (catalogResponse['model_inputs'] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final catalog = {
        for (final feature in features) feature['name'] as String: feature,
      };
      final expected = <String>{
        'family_size',
        'monthly_income_per_capita',
        ..._ageFields,
        ..._housingFields,
        ..._waterFields,
        ..._disasterFields,
        ..._assetFields,
        ..._subscriptionFields,
        ..._philHealthFields,
        ..._programChoices.keys,
      };
      if (features.length != 46 ||
          catalog.keys.toSet().length != 46 ||
          !catalog.keys.toSet().containsAll(expected) ||
          !expected.containsAll(catalog.keys)) {
        throw const FormatException(
          'Backend feature catalog does not match the 46 APIS inputs.',
        );
      }
      if (!mounted) return;
      setState(() {
        _households = (results[0] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _assessments = (results[1] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _catalog
          ..clear()
          ..addAll(catalog);
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetProgramSelections() {
    for (final entry in _programChoices.entries) {
      _programSelections[entry.key] = List<int?>.filled(
        entry.value.length,
        null,
      );
    }
  }

  // Only completed Yes/No sets replace a previously saved count.
  // An incomplete new set remains NULL, never zero.
  int? _programCount(String field) {
    final answers = _programSelections[field]!;
    if (answers.every((answer) => answer != null)) {
      return answers.where((answer) => answer == 1).length;
    }
    return _number(field);
  }

  void _reset() {
    setState(() {
      _editingId = null;
      _selectedHousehold = null;
      _assessmentDate = DateTime.now();
      _dataOrigin = 'synthetic';
      _confirmedSingleFamily = false;
      _answers.clear();
      _resetProgramSelections();
      _incomeController.clear();
      for (final controller in _numbers.values) {
        controller.clear();
      }
      _formVersion++;
    });
  }

  void _populate(Map<String, dynamic> assessment) {
    if (assessment['has_classification'] == true) {
      _message(
        'Assessment Locked',
        'This assessment has a classification. Create a new assessment to update household evidence.',
      );
      return;
    }
    final householdId = (assessment['household_id'] as num).toInt();
    final matches = _households.where((h) => h['household_id'] == householdId);
    if (matches.isEmpty) {
      _message(
        'Household unavailable',
        'Refresh the registered household list.',
      );
      return;
    }
    setState(() {
      _editingId = (assessment['assessment_id'] as num).toInt();
      _selectedHousehold = matches.first;
      _assessmentDate = DateTime.parse(
        assessment['assessment_date'].toString(),
      );
      _dataOrigin = assessment['data_origin'] == 'lgu_authorized'
          ? 'lgu_authorized'
          : 'synthetic';
      _confirmedSingleFamily = true;
      _answers.clear();
      _resetProgramSelections();
      for (final feature in _catalog.values) {
        final name = feature['name'] as String;
        final value = assessment[name];
        if (feature['kind'] == 'code' && value is num) {
          _answers[name] = value.toInt();
        }
      }
      for (final entry in _numbers.entries) {
        final value = assessment[entry.key];
        entry.value.text = value == null ? '' : '$value';
      }
      _incomeController.text = assessment['monthly_income']?.toString() ?? '';
      _formVersion++;
    });
  }

  Future<void> _message(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _assessmentDate,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
    );
    if (value != null && mounted) setState(() => _assessmentDate = value);
  }

  String _label(String name) {
    const custom = <String, String>{
      'members_age_0_5': 'Members aged 0–5',
      'members_age_6_11': 'Members aged 6–11',
      'members_age_12_17': 'Members aged 12–17',
      'members_age_60_plus': 'Members aged 60+',
      'outer_wall_material': 'Outer wall material',
      'disaster_preparedness_kit': 'Emergency go bag / disaster kit',
      'experienced_natural_disaster': 'Experienced a natural disaster?',
      'disaster_evacuated_or_displaced': 'Displaced or evacuated?',
      'recovered_from_disaster': 'Recovered from the disaster?',
      'philhealth_membership_status': 'PhilHealth membership',
      'received_philhealth_benefits': 'PhilHealth benefits (past 6 months)?',
      'social_insurance_program_count': 'Social insurance programs (count)',
      'social_assistance_program_count': 'Social assistance programs (count)',
      'labor_market_program_count': 'Labor market programs (count)',
      'government_services_accessed_count':
          'Government services accessed (count)',
    };
    return custom[name] ?? (_catalog[name]?['label']?.toString() ?? name);
  }

  Map<int, String> _options(String name) {
    if (name == 'philhealth_membership_status') {
      return {1: 'Yes — paying member', 2: 'Yes — non-paying member', 3: 'No'};
    }
    final pufName = _surveyChoices[name];
    if (pufName != null && apis2022Options[pufName] != null) {
      return apis2022Options[pufName]!;
    }
    return {1: 'Yes', 2: 'No'};
  }

  Widget _answerField(String name, {bool hideHelper = false}) {
    final spec = _catalog[name]!;
    if (spec['kind'] == 'code') {
      final allowed = (spec['options'] as List)
          .map((v) => (v as num).toInt())
          .toSet();
      final options = _options(name);
      return DropdownButtonFormField<int>(
        key: ValueKey('$_formVersion-$name'),
        initialValue: _answers[name],
        isExpanded: true,
        decoration: InputDecoration(labelText: _label(name)),
        items: [
          const DropdownMenuItem<int>(
            value: null,
            child: Text('Unknown / not answered'),
          ),
          for (final code in allowed.toList()..sort())
            DropdownMenuItem<int>(
              value: code,
              child: Text(
                options[code] ?? 'Code $code',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _saving
            ? null
            : (value) {
                setState(() {
                  _answers[name] = value;
                  if (name == 'experienced_natural_disaster' && value != 1) {
                    _answers['disaster_evacuated_or_displaced'] = null;
                    _answers['recovered_from_disaster'] = null;
                  }
                });
              },
      );
    }
    final max = _numericRanges[name]!;
    final programCount = <String>{
      'social_insurance_program_count',
      'social_assistance_program_count',
      'labor_market_program_count',
      'government_services_accessed_count',
    }.contains(name);
    return TextFormField(
      controller: _numbers[name],
      enabled: !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: _label(name),
        hintText: name == 'bedroom_count'
            ? 'e.g. 2'
            : programCount
            ? '0 if none (max $max)'
            : '0 if none',
        helperText: hideHelper
            ? null
            : programCount
            ? 'Count different programs, not people.'
            : null,
      ),
      validator: (text) {
        final raw = (text ?? '').trim();
        if (raw.isEmpty) return null;
        final value = int.tryParse(raw);
        if (value == null || value < 0 || value > max) {
          return 'Enter a whole number from 0 to $max.';
        }
        return null;
      },
      onChanged: (_) => setState(() {}),
    );
  }

  // Equal-width answer controls keep each question aligned on mobile and web.
  Widget _programAnswerChip({
    required String label,
    required int? option,
    required int? selected,
    required VoidCallback onTap,
  }) {
    final active = option == selected;
    final activeTextColor = option == 1
        ? AppColors.primaryGreen
        : option == 2
        ? AppColors.darkText
        : AppColors.greyText;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? activeTextColor : AppColors.greyText,
        backgroundColor: active
            ? option == 1
                  ? AppColors.lightGreen
                  : const Color(0xFFF2F4F3)
            : AppColors.white,
        side: BorderSide(
          color: active ? activeTextColor : AppColors.borderColor,
          width: active ? 1.3 : 1,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 39),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  // The standard scrollable AlertDialog avoids nested scrolling constraints.
  // The draft answers are committed only when Apply answers is pressed.
  Future<void> _openProgramDialog(String field) async {
    if (_saving) return;
    final options = _programChoices[field]!;
    final draft = List<int?>.from(_programSelections[field]!);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final answered = draft.where((answer) => answer != null).length;
          final yesCount = draft.where((answer) => answer == 1).length;
          final complete = answered == options.length;
          final oldCount = _number(field);

          return AlertDialog(
            backgroundColor: AppColors.white,
            surfaceTintColor: Colors.transparent,
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 18,
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
            contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
            actionsPadding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    size: 21,
                    color: AppColors.primaryGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _programTitles[field]!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _programPrompts[field]!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.greyText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          complete
                              ? '$yesCount applicable ${yesCount == 1 ? 'category' : 'categories'}'
                              : '$answered of ${options.length} answered',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                      if (!complete && oldCount != null)
                        Text(
                          'Saved: $oldCount',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.greyText,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: answered / options.length,
                      minHeight: 5,
                      backgroundColor: AppColors.borderColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: [
                      TextButton.icon(
                        onPressed: () => setDialogState(() {
                          draft.fillRange(0, options.length, 2);
                        }),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('None apply'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryGreen,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setDialogState(() {
                          draft.fillRange(0, options.length, null);
                        }),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Clear answers'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.greyText,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18, color: AppColors.borderColor),
                  for (var index = 0; index < options.length; index++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 27,
                                height: 27,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.lightGreen,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  String.fromCharCode(65 + index),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryGreen,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    options[index],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Row(
                            children: [
                              Expanded(
                                child: _programAnswerChip(
                                  label: 'Yes',
                                  option: 1,
                                  selected: draft[index],
                                  onTap: () =>
                                      setDialogState(() => draft[index] = 1),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _programAnswerChip(
                                  label: 'No',
                                  option: 2,
                                  selected: draft[index],
                                  onTap: () =>
                                      setDialogState(() => draft[index] = 2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _programAnswerChip(
                                  label: 'Unknown',
                                  option: null,
                                  selected: draft[index],
                                  onTap: () =>
                                      setDialogState(() => draft[index] = null),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (index != options.length - 1)
                      const Divider(height: 1, color: AppColors.borderColor),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.greyText,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _programSelections[field] = List<int?>.from(draft);
                  });
                  Navigator.of(dialogContext).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Apply answers'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _programSummary(String field) {
    final options = _programChoices[field]!;
    final answers = _programSelections[field]!;
    final answered = answers.where((value) => value != null).length;
    final complete = answered == options.length;
    final count = _programCount(field);
    final status = complete
        ? '${count ?? 0} applicable categories'
        : count != null
        ? 'Saved count: $count · $answered/${options.length} reviewed'
        : answered > 0
        ? '$answered/${options.length} answered · Not verified'
        : 'Not yet verified';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderColor),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: _saving ? null : () => _openProgramDialog(field),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    color: AppColors.primaryGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _programTitles[field]!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkText,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        style: const TextStyle(
                          color: AppColors.greyText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: AppColors.primaryGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnlyMemberField(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(
          Icons.lock_outline,
          size: 18,
          color: AppColors.primaryGreen,
        ),
      ),
      isEmpty: false,
      child: Text(
        value,
        style: const TextStyle(fontSize: 16, color: AppColors.darkText),
      ),
    );
  }

  Widget _card({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.borderColor),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
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
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }

  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, size) => Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        for (final child in children)
          SizedBox(
            width: size.maxWidth >= 670
                ? (size.maxWidth - 16) / 2
                : size.maxWidth,
            child: child,
          ),
      ],
    ),
  );

  Widget _group(
    String title,
    String subtitle,
    IconData icon,
    List<String> names,
  ) {
    final visible = names
        .where(
          (name) =>
              name != 'disaster_evacuated_or_displaced' &&
                  name != 'recovered_from_disaster' ||
              _answers['experienced_natural_disaster'] == 1,
        )
        .toList();
    return _card(
      title: title,
      subtitle: subtitle,
      icon: icon,
      child: _grid(visible.map(_answerField).toList()),
    );
  }

  bool _checkBeforeSave() {
    if (_selectedHousehold == null) {
      _message('Incomplete Assessment', 'Select a registered household.');
      return false;
    }
    if (!_confirmedSingleFamily) {
      _message(
        'Family size confirmation',
        'Confirm that the registered household represents one family before saving.',
      );
      return false;
    }
    if (_selectedHousehold!['members_complete'] == false) {
      _message(
        'Incomplete Registration',
        'Complete the household member roster in Registration first.',
      );
      return false;
    }
    final size = _familySize;
    if (size == null || size < 1 || _ageSubtotal > size) {
      _message(
        'Invalid age counts',
        'Age-band counts cannot exceed the registered family size.',
      );
      return false;
    }
    // All four selected APIS age bands plus remaining ages (18–59) total family size.
    if (_incomeController.text.trim().isNotEmpty && _income == null) {
      _message('Invalid income', 'Enter a valid monthly family income.');
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false) || !_checkBeforeSave()) {
      return;
    }
    final data = <String, dynamic>{
      'household_id': _selectedHousehold!['household_id'],
      'assessment_date': _dateText(_assessmentDate),
      'data_origin': _dataOrigin,
      // family_size and region_code are verified by FastAPI from Registration.
      'monthly_income': _incomeController.text.trim().isEmpty
          ? null
          : _incomeController.text.trim().replaceAll(',', ''),
      for (final entry in _numbers.entries)
        entry.key: _programChoices.containsKey(entry.key)
            ? _programCount(entry.key)
            : _number(entry.key),
      for (final field in _catalog.values)
        if (field['kind'] == 'code')
          (field['name'] as String): _answers[field['name']],
    };
    if (_answers['experienced_natural_disaster'] != 1) {
      data['disaster_evacuated_or_displaced'] = null;
      data['recovered_from_disaster'] = null;
    }
    setState(() => _saving = true);
    try {
      if (_editingId == null) {
        await VulnerabilityService.createAssessment(data);
      } else {
        await VulnerabilityService.updateAssessment(_editingId!, data);
      }
      if (!mounted) return;
      _reset();
      try {
        final refreshed = await VulnerabilityService.fetchAssessments();
        if (mounted) setState(() => _assessments = refreshed);
      } catch (_) {
        // Saving succeeded; staff can refresh the record list later.
      }
      await _message(
        'Assessment Saved',
        'The household assessment was saved successfully.',
      );
    } catch (error) {
      await _message('Assessment Not Saved', _errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _history() => _card(
    title: 'Assessment Records',
    subtitle: 'Saved assessments. Classified records cannot be edited.',
    icon: Icons.history_outlined,
    child: _assessments.isEmpty
        ? const Text(
            'No assessment records found.',
            style: TextStyle(color: AppColors.greyText),
          )
        : Column(
            children: [
              for (final assessment in _assessments) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${assessment['household_head'] ?? 'Household'} '
                              '(HH-${assessment['household_id']})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Assessment ${assessment['assessment_id']} · '
                              '${assessment['assessment_date']} · '
                              '${assessment['barangay'] ?? ''}',
                              style: const TextStyle(
                                color: AppColors.greyText,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Monthly income per capita: '
                              '${assessment['monthly_income_per_capita'] ?? 'Not recorded'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.greyText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            _saving || assessment['has_classification'] == true
                            ? null
                            : () => _populate(assessment),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.borderColor),
              ],
            ],
          ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(50),
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unable to load household assessments: $_error'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
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
                    SizedBox(height: 4),
                    Text(
                      'Record household information for vulnerability assessment.',
                      style: TextStyle(color: AppColors.greyText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _saving ? null : _load,
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_editingId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Editing assessment #$_editingId',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _reset,
                    child: const Text('Cancel edit'),
                  ),
                ],
              ),
            ),
          _card(
            title: 'Household Information',
            subtitle: 'Select an LGU-registered household; address and family size come from Registration.',
            icon: Icons.home_work_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => DropdownMenu<int>(
                    key: ValueKey('household-$_formVersion'),
                    width: constraints.maxWidth,
                    enableFilter: true,
                    enableSearch: true,
                    requestFocusOnTap: true,
                    menuHeight: 300,
                    enabled: !_saving && _editingId == null,
                    initialSelection:
                        (_selectedHousehold?['household_id'] as num?)?.toInt(),
                    label: const Text('Registered Household'),
                    hintText: 'Search by household, head, or barangay',
                    dropdownMenuEntries: [
                      for (final household in _households)
                        DropdownMenuEntry<int>(
                          value: (household['household_id'] as num).toInt(),
                          label:
                              'HH-${household['household_id']} · '
                              '${household['household_head']} · ${household['barangay']}',
                        ),
                    ],
                    onSelected: (id) {
                      if (id == null) return;
                      final h = _households.firstWhere(
                        (household) => household['household_id'] == id,
                      );
                      setState(() {
                        _selectedHousehold = h;
                        _confirmedSingleFamily = false;
                        _answers.clear();
                        _resetProgramSelections();
                        _incomeController.clear();
                        for (final c in _numbers.values) {
                          c.clear();
                        }
                        _formVersion++;
                      });
                    },
                  ),
                ),
                if (_selectedHousehold != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Household head: ${_selectedHousehold!['household_head']}',
                  ),
                  Text('Barangay: ${_selectedHousehold!['barangay']}'),
                  Text(
                    'Registered family size: ${_familySize ?? 'Not recorded'}',
                  ),
                ],
                const SizedBox(height: 10),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _confirmedSingleFamily,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _confirmedSingleFamily = value ?? false,
                        ),
                  title: const Text(
                    'The registered household represents one family',
                  ),
                  subtitle: const Text(
                    'Family income and member counts must refer to the same family.',
                  ),
                ),
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _chooseDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Assessment date: ${_dateText(_assessmentDate)}'),
                ),
              ],
            ),
          ),
          _card(
            title: 'Household Members',
            subtitle:
                'Enter the number of members in each age group (0 if none).',
            icon: Icons.groups_outlined,
            child: _grid([
              _answerField('members_age_0_5', hideHelper: true),
              _answerField('members_age_6_11', hideHelper: true),
              _answerField('members_age_12_17', hideHelper: true),
              _readOnlyMemberField(
                'Members aged 18–59 (calculated)',
                _workingAgeCount?.toString() ?? '—',
              ),
              _answerField('members_age_60_plus', hideHelper: true),
              _readOnlyMemberField(
                'Total registered members',
                _familySize?.toString() ?? '—',
              ),
            ]),
          ),
          _group(
            'Housing and Electricity',
            'Housing materials, number of bedrooms, and electricity access.',
            Icons.home_outlined,
            _housingFields,
          ),
          _group(
            'Water and Sanitation',
            'Drinking water and toilet facilities.',
            Icons.water_drop_outlined,
            _waterFields,
          ),
          _group(
            'Disaster Preparedness and Recovery',
            'Follow-up questions appear when the family experienced a disaster.',
            Icons.health_and_safety_outlined,
            _disasterFields,
          ),
          _group(
            'Household Assets',
            'Select Yes or No for each owned item.',
            Icons.devices_other_outlined,
            _assetFields,
          ),
          _group(
            'Subscriptions',
            'Services used by the household.',
            Icons.wifi_outlined,
            _subscriptionFields,
          ),
          _card(
            title: 'Household Income',
            subtitle:
                'Enter the family’s total monthly income in Philippine pesos.',
            icon: Icons.payments_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _incomeController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      final valid = RegExp(r'^\d{0,12}(\.\d{0,2})?$')
                          .hasMatch(newValue.text);
                      return valid ? newValue : oldValue;
                    }),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Monthly family income (PHP)',
                    hintText: 'e.g. 15000.00',
                    prefixText: '₱ ',
                    helperText: 'Enter 0 if none; leave blank if unknown.',
                  ),
                  validator: (text) {
                    final raw = (text ?? '').trim().replaceAll(',', '');
                    if (raw.isEmpty) return null;
                    if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(raw)) {
                      return 'Enter a valid amount (e.g. 15000.00).';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Monthly income per person (calculated): '
                  '${_perCapita == null ? '—' : '₱${_perCapita!.toStringAsFixed(2)}'}',
                  style: const TextStyle(
                    color: AppColors.greyText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _card(
            title: 'Health and Social Protection',
            subtitle:
                'PhilHealth coverage, assistance, and government services.',
            icon: Icons.volunteer_activism_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _grid(_philHealthFields.map(_answerField).toList()),
                const SizedBox(height: 22),
                const Divider(color: AppColors.borderColor),
                const SizedBox(height: 14),
                const Text(
                  'Programs and Services',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select a category to review its questionnaire choices.',
                  style: TextStyle(fontSize: 12, color: AppColors.greyText),
                ),
                const SizedBox(height: 14),
                for (final field in _programChoices.keys)
                  _programSummary(field),
              ],
            ),
          ),
          _card(
            title: 'Assessment Information Source',
            subtitle: 'Choose the actual source of the answers.',
            icon: Icons.verified_user_outlined,
            child: DropdownButtonFormField<String>(
              key: ValueKey('origin-$_formVersion'),
              initialValue: _dataOrigin,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Data origin'),
              items: const [
                DropdownMenuItem<String>(
                  value: 'synthetic',
                  child: Text(
                    'Demo / practice entry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem<String>(
                  value: 'lgu_authorized',
                  child: Text(
                    'Verified LGU household assessment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => _dataOrigin = value);
                    },
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
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
                _saving
                    ? 'Saving Assessment...'
                    : (_editingId == null
                          ? 'Save Household Assessment'
                          : 'Update Household Assessment'),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _history(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
