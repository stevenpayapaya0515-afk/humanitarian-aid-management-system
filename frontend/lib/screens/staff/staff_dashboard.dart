import '../../widgets/aidtrack_section_card.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../households/household_registration.dart';
import '../assessment/household_assessment.dart';
import '../vulnerability_classification/vulnerability_classification.dart';
import 'staff_settings.dart';
import '../beneficiaries/beneficiary_management.dart';
import '../distribution/aid_distribution.dart';
import '../reports/staff_report.dart';
import '../../widgets/aidtrack_module_loading.dart';

class StaffDashboard extends StatefulWidget {
  final VoidCallback? onLogout;
  const StaffDashboard({super.key, this.onLogout});
  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  String _selectedPage = AuthService.initialPageForRole('Staff');
  String get selectedPage => _selectedPage;
  set selectedPage(String page) {
    _selectedPage = page;
    AuthService.rememberPage('Staff', page);
  }
  String _staffName = 'LGU Staff';
  Future<void> _loadStaffProfile() async {
    try {
      final token = AuthService.accessToken;
      if (token == null || token.isEmpty) return;
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/auth/me'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted || response.statusCode != 200) return;
      if (AuthService.accessToken != token) return;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return;
      final name = data['full_name'];
      if (name is! String || name.trim().isEmpty) return;
      setState(() {
        _staffName = name.trim();
      });
    } catch (_) {}
  }

  int? _totalHouseholds;
  int? _totalPopulation;
  int? _assessedHouseholds;
  int? _classifiedHouseholds;
  int? _lowVulnerability;
  int? _mediumVulnerability;
  int? _highVulnerability;
  int? _aidDistributions;
  List<Map<String, dynamic>> _recentActivity = [];
  bool _dashboardLoading = false;
  String? _dashboardError;
  int _dashboardRequestId = 0;
  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadStaffProfile();
  }

  Future<void> _loadDashboard() async {
    final requestId = ++_dashboardRequestId;
    setState(() {
      _dashboardLoading = true;
      _dashboardError = null;
    });
    try {
      final token = AuthService.accessToken;
      if (token == null || token.isEmpty) {
        throw const AuthException('Please log in again.');
      }
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/dashboard/summary'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        throw const AuthException(
          'Your session has expired. Please log out and log in again.',
        );
      }
      if (response.statusCode == 403) {
        throw const AuthException('Your account cannot access the dashboard.');
      }
      if (response.statusCode != 200) {
        throw const AuthException(
          'Unable to load dashboard information. Please try again.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid dashboard response.');
      }
      final households = data['total_households'];
      final population = data['total_population'];
      final assessed = data['assessed_households'];
      final classified = data['classified_households'];
      final low = data['low_vulnerability'];
      final medium = data['medium_vulnerability'];
      final high = data['high_vulnerability'];
      final distributions = data['aid_distributions'];
      if (households is! int ||
          households < 0 ||
          population is! int ||
          population < 0 ||
          assessed is! int ||
          assessed < 0 ||
          classified is! int ||
          classified < 0 ||
          low is! int ||
          low < 0 ||
          medium is! int ||
          medium < 0 ||
          high is! int ||
          high < 0) {
        throw const FormatException('Invalid dashboard statistics.');
      }
      int? aidDistributions;
      if (distributions != null) {
        if (distributions is! int || distributions < 0) {
          throw const FormatException('Invalid aid distribution total.');
        }
        aidDistributions = distributions;
      }
      final activityRows = data['recent_activity'];
      if (activityRows is! List) {
        throw const FormatException('Invalid recent activity response.');
      }
      final activities = <Map<String, dynamic>>[];
      for (final item in activityRows) {
        if (item is! Map) {
          throw const FormatException('Invalid activity record.');
        }
        final activity = Map<String, dynamic>.from(item);
        if (activity['activity_type'] is! String ||
            activity['description'] is! String ||
            activity['occurred_at'] is! String) {
          throw const FormatException('Incomplete activity record.');
        }
        activities.add(activity);
      }
      if (!mounted || requestId != _dashboardRequestId) {
        return;
      }
      setState(() {
        _totalHouseholds = households;
        _totalPopulation = population;
        _assessedHouseholds = assessed;
        _classifiedHouseholds = classified;
        _lowVulnerability = low;
        _mediumVulnerability = medium;
        _highVulnerability = high;
        _aidDistributions = aidDistributions;
        _recentActivity = activities;
      });
    } catch (error) {
      if (!mounted || requestId != _dashboardRequestId) {
        return;
      }
      String message;
      if (error is AuthException) {
        message = error.message;
      } else if (error is TimeoutException) {
        message = 'The server took too long. Please try again.';
      } else if (error is http.ClientException) {
        message = 'Cannot connect to the server. Check your connection.';
      } else {
        message = 'Unable to load dashboard information.';
      }
      setState(() {
        _dashboardError = message;
      });
    } finally {
      if (mounted && requestId == _dashboardRequestId) {
        setState(() {
          _dashboardLoading = false;
        });
      }
    }
  }

  Future<void> _showDashboardErrorDialog(String message) async {
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
            const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 58),
            const SizedBox(height: 14),
            const Text(
              'Dashboard Refresh Failed',
              textAlign: TextAlign.center,
              style: TextStyle(
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
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDashboardWithFeedback() async {
    if (_dashboardLoading) return;
    await _loadDashboard();
    if (!mounted) return;
    if (_dashboardError != null) {
      await _showDashboardErrorDialog(_dashboardError!);
    }
  }

  final List<Map<String, dynamic>> menuItems = [
    {'title': 'Dashboard', 'icon': Icons.dashboard_outlined},
    {'title': 'Household Registration', 'icon': Icons.home_outlined},
    {'title': 'Household Assessment', 'icon': Icons.assignment_outlined},
    {'title': 'Vulnerability Classification', 'icon': Icons.analytics_outlined},
    {'title': 'Beneficiary Management', 'icon': Icons.people_outline},
    {'title': 'Aid Distribution', 'icon': Icons.inventory_2_outlined},
    {'title': 'Reports', 'icon': Icons.bar_chart_outlined},
    {'title': 'Settings', 'icon': Icons.settings_outlined},
  ];
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;
        return Scaffold(
          backgroundColor: AppColors.primaryGreen,
          drawer: isMobile
              ? Drawer(child: _buildSidebar(isMobile: true))
              : null,
          appBar: isMobile
              ? AppBar(
                  backgroundColor: AppColors.primaryGreen,
                  surfaceTintColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  leadingWidth: 68,
                  leading: Builder(
                    builder: (context) => Center(
                      child: IconButton(
                        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                        tooltip: 'Open navigation menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: SizedBox(
                          width: 32,
                          height: 24,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final color in const [
                                Colors.white,
                                AppColors.accentYellow,
                                Colors.white,
                              ])
                                Container(
                                  width: color == AppColors.accentYellow ? 18 : 32,
                                  margin: EdgeInsets.only(left: color == AppColors.accentYellow ? 4 : 0),
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  titleSpacing: 0,
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Aid',
                              style: TextStyle(color: Colors.white),
                            ),
                            TextSpan(
                              text: 'Track',
                              style: TextStyle(color: AppColors.accentYellow),
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          body: Row(
            children: [
              // Keep the green sidebar curved inward at the bottom-right.
              if (!isMobile)
                ColoredBox(
                  color: const Color(0xFFF5F8F5),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(15),
                    ),
                    child: _buildSidebar(isMobile: false),
                  ),
                ),

              // The main panel curves into the green sidebar at the top-left.
              Expanded(
                child: ClipRRect(
                  borderRadius: isMobile
                      ? BorderRadius.zero
                      : const BorderRadius.only(topLeft: Radius.circular(28)),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: const Color(0xFFF5F8F5),
                    child: ProgressIndicatorTheme(
                      data: const ProgressIndicatorThemeData(
                        color: AppColors.primaryGreen,
                      ),
                      child: _buildMainContent(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar({required bool isMobile}) {
    return Container(
      width: 250,
      color: AppColors.primaryGreen,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Image.asset(
                      'assets/images/aidtrack_symbol.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Aid',
                            style: TextStyle(color: AppColors.white),
                          ),
                          TextSpan(
                            text: 'Track',
                            style: TextStyle(color: AppColors.accentYellow),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
                itemCount: menuItems.length,
                itemExtent: isMobile ? 50 : 46,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final title = item['title'] as String;
                  final isSelected = selectedPage == title;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Material(
                      color: isSelected
                          ? AppColors.accentYellow
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onTap: () {
                          setState(() {
                            selectedPage = title;
                          });
                          if (isMobile) {
                            Navigator.pop(context);
                          }
                          if (title == 'Dashboard') {
                            _loadDashboard();
                            _loadStaffProfile();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                size: 20,
                                color: isSelected
                                    ? AppColors.primaryGreen
                                    : Colors.white70,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.primaryGreen
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: Colors.white24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.person_outline,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Tooltip(
                              message: _staffName,
                              child: Text(
                                _staffName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'LGU Staff',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final shouldLogout = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (dialogContext) {
                            return AlertDialog(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              title: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.logout_rounded,
                                    color: AppColors.primaryGreen,
                                    size: 52,
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'Confirm Logout',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                ],
                              ),
                              content: const Text(
                                'Are you sure you want to log out of your account?',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.greyText,
                                ),
                              ),
                              actionsAlignment: MainAxisAlignment.center,
                              actions: [
                                SizedBox(
                                  width: 260,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () {
                                            Navigator.of(dialogContext)
                                                .pop(false);
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.primaryGreen,
                                            side: const BorderSide(
                                              color: AppColors.primaryGreen,
                                            ),
                                            minimumSize: const Size(0, 45),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: () {
                                            Navigator.of(dialogContext)
                                                .pop(true);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFFB71C1C,
                                            ),
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(0, 45),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                          ),
                                          child: const Text('Log Out'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        if (!mounted || shouldLogout != true) return;
                        AuthService.logout();
                        if (widget.onLogout != null) {
                          widget.onLogout!();
                          return;
                        }
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      key: ValueKey(selectedPage),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 18),
          if (selectedPage == 'Dashboard')
            _buildDashboardOverview()
          else if (selectedPage == 'Household Registration')
            const HouseholdRegistration()
          else if (selectedPage == 'Household Assessment')
            const HouseholdAssessmentScreen()
          else if (selectedPage == 'Vulnerability Classification')
            const VulnerabilityClassificationScreen()
          else if (selectedPage == 'Beneficiary Management')
            const BeneficiaryManagementScreen()
          else if (selectedPage == 'Aid Distribution')
            const AidDistributionScreen()
          else if (selectedPage == 'Reports')
            const StaffReportScreen(showHeading: false)
          else if (selectedPage == 'Settings')
            const StaffSettings(),
        ],
      ),
    );
  }

  String _pageSubtitle() {
    switch (selectedPage) {
      case 'Dashboard':
        return 'Overview of household, assessment, and aid distribution activity.';
      case 'Reports':
        return 'Household vulnerability and aid distribution overview';
      case 'Household Registration':
        return 'Register and manage household records.';
      case 'Household Assessment':
        return 'Record and review household assessments.';
      case 'Vulnerability Classification':
        return 'Review household vulnerability classifications.';
      case 'Beneficiary Management':
        return 'Review beneficiary eligibility and status.';
      case 'Aid Distribution':
        return 'Manage aid distribution records.';
      case 'Settings':
        return 'Manage your staff account settings.';
      default:
        return '';
    }
  }

  IconData _pageIcon() {
    switch (selectedPage) {
      case 'Dashboard':
        return Icons.bar_chart_rounded;
      case 'Reports':
        return Icons.insert_chart_outlined_rounded;
      case 'Household Registration':
        return Icons.home_outlined;
      case 'Household Assessment':
        return Icons.assignment_outlined;
      case 'Vulnerability Classification':
        return Icons.analytics_outlined;
      case 'Beneficiary Management':
        return Icons.people_outline;
      case 'Aid Distribution':
        return Icons.local_shipping_outlined;
      default:
        return Icons.settings_outlined;
    }
  }

  Widget _buildPageHeader() {
    return AidTrackSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F4E9),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(_pageIcon(), color: AppColors.primaryGreen, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedPage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _pageSubtitle(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.greyText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.account_balance_outlined,
            color: Colors.black87,
            size: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardOverview() {
    String display(int? value) {
      if (_dashboardLoading && value == null) return '…';
      return value?.toString() ?? '—';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _dashboardLoading ? null : _refreshDashboardWithFeedback,
            icon: _dashboardLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
            label: Text(_dashboardLoading ? 'Refreshing...' : 'Refresh totals'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
            ),
          ),
        ),
        if (_dashboardError != null) ...[
          Text(_dashboardError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 970
                ? 5
                : width >= 670
                ? 3
                : width >= 400
                ? 2
                : 1;
            final cardWidth = (width - (columns - 1) * 14) / columns;
            final cards = <(String, String, IconData)>[
              (
                'Total Households',
                display(_totalHouseholds),
                Icons.home_outlined,
              ),
              (
                'Household Population',
                display(_totalPopulation),
                Icons.people_outline,
              ),
              (
                'Assessed Households',
                display(_assessedHouseholds),
                Icons.assignment_turned_in_outlined,
              ),
              (
                'Classified Households',
                display(_classifiedHouseholds),
                Icons.analytics_outlined,
              ),
              (
                'Aid Distributions',
                display(_aidDistributions),
                Icons.local_shipping_outlined,
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  _buildSummaryCard(
                    width: cardWidth,
                    title: card.$1,
                    value: card.$2,
                    icon: card.$3,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _dashboardTwoColumns(
          equalHeight: true,
          left: _buildDashboardPanel(
            title: 'Vulnerability Summary',
            subtitle: 'Classified households by vulnerability level.',
            icon: Icons.shield_outlined,
            child: _buildVulnerabilityOverview(),
          ),
          right: _buildDashboardPanel(
            title: 'Quick Actions',
            subtitle: 'Common staff tasks for household and aid management.',
            icon: Icons.bolt_outlined,
            child: _buildQuickActions(),
          ),
        ),
        const SizedBox(height: 20),
        _dashboardTwoColumns(
          left: _buildDashboardPanel(
            title: 'Recent Activity',
            subtitle: 'Latest recorded household and assessment activity.',
            icon: Icons.history_outlined,
            child: _buildRecentActivity(),
          ),
          right: _buildDashboardPanel(
            title: 'Needs Attention',
            subtitle: 'Current totals that may require staff review.',
            icon: Icons.fact_check_outlined,
            child: _buildAttentionSummary(),
          ),
        ),
        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Local Government Unit • Authorized Personnel Only',
            style: TextStyle(fontSize: 11, color: AppColors.greyText),
          ),
        ),
      ],
    );
  }

  Widget _dashboardTwoColumns({
    required Widget left,
    required Widget right,
    bool equalHeight = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 780) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 18), right],
          );
        }
        final row = Row(
          crossAxisAlignment: equalHeight
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 18),
            Expanded(child: right),
          ],
        );
        if (equalHeight) {
          final height = constraints.maxWidth < 940 ? 314.0 : 286.0;
          return SizedBox(height: height, child: row);
        }
        return row;
      },
    );
  }

  Widget _buildQuickActions() {
    final actions = <(String, IconData)>[
      ('Household Registration', Icons.home_outlined),
      ('Household Assessment', Icons.assignment_turned_in_outlined),
      ('Vulnerability Classification', Icons.analytics_outlined),
      ('Aid Distribution', Icons.local_shipping_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 330 ? 2 : 1;
        final tileWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final action in actions)
              SizedBox(
                width: tileWidth,
                height: 68,
                child: Material(
                  color: const Color(0xFFF8FBF8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFA8CBB1)),
                  ),
                  child: InkWell(
                    onTap: () => setState(() => selectedPage = action.$1),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9F5EC),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              action.$2,
                              size: 20,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              action.$1,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.darkText,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 17,
                            color: AppColors.primaryGreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAttentionSummary() {
    final pending = _assessedHouseholds != null && _classifiedHouseholds != null
        ? (_assessedHouseholds! - _classifiedHouseholds!)
              .clamp(0, 999999999)
              .toInt()
        : null;
    return Column(
      children: [
        _attentionRow(
          'Assessed, not yet classified',
          'Difference between assessed and classified household totals.',
          Icons.assignment_late_outlined,
          pending,
          'Vulnerability Classification',
        ),
        const Divider(height: 24, color: Color(0xFFE4EBE5)),
        _attentionRow(
          'High vulnerability',
          'Latest High classifications for staff review.',
          Icons.report_problem_outlined,
          _highVulnerability,
          'Vulnerability Classification',
        ),
        const SizedBox(height: 12),
        const Text(
          'These are report totals, not assigned work items. Staff must review classifications before aid decisions.',
          style: TextStyle(fontSize: 11, color: AppColors.greyText),
        ),
      ],
    );
  }

  Widget _attentionRow(
    String title,
    String subtitle,
    IconData icon,
    int? count,
    String target,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => selectedPage = target),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              _dashboardIcon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.greyText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${count ?? '—'}',
                style: const TextStyle(
                  color: AppColors.primaryGreen,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.primaryGreen,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F5EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.primaryGreen, size: 23),
    );
  }

  Widget _buildVulnerabilityOverview() {
    if (_dashboardLoading && _totalHouseholds == null) {
      return const AidTrackModuleLoading();
    }
    final total = _classifiedHouseholds ?? 0;
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No classification data available yet.',
          style: TextStyle(color: AppColors.greyText),
        ),
      );
    }
    final segments = <(String, int, Color, Color)>[
      (
        'Low',
        _lowVulnerability ?? 0,
        const Color(0xFF278E43),
        const Color(0xFFEDF9EF),
      ),
      (
        'Medium',
        _mediumVulnerability ?? 0,
        const Color(0xFFBD8500),
        const Color(0xFFFFF8E5),
      ),
      (
        'High',
        _highVulnerability ?? 0,
        const Color(0xFFB4232E),
        const Color(0xFFFFEDEE),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 330 ? 3 : 1;
            final tileWidth =
                (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in segments)
                  Container(
                    width: tileWidth,
                    height: 108,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: item.$4,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(backgroundColor: item.$3, radius: 5),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                item.$1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${item.$2}',
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.bold,
                            color: item.$3,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          'Latest classification for $total households. Predictions are for staff review.',
          style: const TextStyle(fontSize: 11, color: AppColors.greyText),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    if (_dashboardLoading && _totalHouseholds == null) {
      return const AidTrackModuleLoading();
    }
    if (_recentActivity.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(35),
        child: Center(
          child: Text(
            'No recent activity available yet.',
            style: TextStyle(color: AppColors.greyText, fontSize: 13),
          ),
        ),
      );
    }
    return Column(
      children: List.generate(_recentActivity.length, (index) {
        final activity = _recentActivity[index];
        final type = activity['activity_type'] as String;
        final description = activity['description'] as String;
        final date = activity['occurred_at'] as String;
        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEAF3EC),
                child: Icon(
                  _activityIcon(type),
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
              ),
              title: Text(
                type,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.darkText,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.greyText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formatActivityDate(date),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.greyText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index < _recentActivity.length - 1)
              const Divider(height: 1, color: Color(0xFFE4EBE5)),
          ],
        );
      }),
    );
  }

  IconData _activityIcon(String type) {
    switch (type) {
      case 'Household Registration':
        return Icons.home_outlined;
      case 'Household Assessment':
        return Icons.assignment_outlined;
      case 'Vulnerability Classification':
        return Icons.analytics_outlined;
      case 'Aid Distribution':
        return Icons.inventory_2_outlined;
      default:
        return Icons.history;
    }
  }

  String _formatActivityDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day}, '
        '${date.year} • $hour:$minute $period';
  }

  Widget _buildSummaryCard({
    required double width,
    required String title,
    required IconData icon,
    String value = '—',
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E2D8), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dashboardIcon(icon),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardPanel({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
  }) {
    return AidTrackSectionCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _dashboardIcon(icon),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.greyText,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
}
