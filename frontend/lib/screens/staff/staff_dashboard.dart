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

// ========================================
// STAFF DASHBOARD
// ========================================

class StaffDashboard extends StatefulWidget {
  final VoidCallback? onLogout;

  const StaffDashboard({super.key, this.onLogout});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  // ========================================
  // STAFF ACCOUNT
  // ========================================

  String selectedPage = 'Dashboard';

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
    } catch (_) {
      // Keep the default account label if the request fails.
    }
  }

  // ========================================
  // DASHBOARD DATA
  // ========================================

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

  // Only the latest request can update the dashboard.
  int _dashboardRequestId = 0;

  @override
  void initState() {
    super.initState();

    _loadDashboard();
    _loadStaffProfile();
  }

  // ========================================
  // LOAD DASHBOARD FROM FASTAPI
  // ========================================

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

      // ========================================
      // READ DASHBOARD STATISTICS
      // ========================================

      final households = data['total_households'];
      final population = data['total_population'];
      final assessed = data['assessed_households'];
      final classified = data['classified_households'];

      final low = data['low_vulnerability'];
      final medium = data['medium_vulnerability'];
      final high = data['high_vulnerability'];

      final distributions = data['simulated_distributions'];

      // Validate required numeric values.
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

      // Aid distributions may be null until the module
      // is connected to the dashboard backend.
      int? aidDistributions;

      if (distributions != null) {
        if (distributions is! int || distributions < 0) {
          throw const FormatException('Invalid aid distribution total.');
        }

        aidDistributions = distributions;
      }

      // ========================================
      // READ RECENT ACTIVITY
      // ========================================

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

      // Ignore outdated requests.
      if (!mounted || requestId != _dashboardRequestId) {
        return;
      }

      // ========================================
      // UPDATE DASHBOARD
      // ========================================

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

  // ========================================
  // DASHBOARD ERROR MODAL
  // ========================================

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

  // ========================================
  // REFRESH DASHBOARD WITH ERROR FEEDBACK
  // ========================================

  Future<void> _refreshDashboardWithFeedback() async {
    if (_dashboardLoading) return;

    await _loadDashboard();

    if (!mounted) return;

    if (_dashboardError != null) {
      await _showDashboardErrorDialog(_dashboardError!);
    }
  }

  // ========================================
  // STAFF SIDEBAR MENU ITEMS
  // ========================================

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

  // ========================================
  // RESPONSIVE STAFF DASHBOARD
  // ========================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: AppColors.primaryGreen,

          // MOBILE SIDEBAR DRAWER
          drawer: isMobile
              ? Drawer(child: _buildSidebar(isMobile: true))
              : null,

          // MOBILE TOP NAVIGATION
          appBar: isMobile
              ? AppBar(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.primaryGreen,

                  title: const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Aid',
                          style: TextStyle(color: AppColors.primaryGreen),
                        ),
                        TextSpan(
                          text: 'Track',
                          style: TextStyle(color: AppColors.accentYellow),
                        ),
                      ],
                    ),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                )
              : null,

          // ========================================
          // MAIN DASHBOARD LAYOUT
          // ========================================
          body: Row(
            children: [
              // DESKTOP SIDEBAR
              if (!isMobile) _buildSidebar(isMobile: false),

              // RIGHT STAFF PANEL
              Expanded(
                child: ClipRRect(
                  borderRadius: isMobile
                      ? BorderRadius.zero
                      : const BorderRadius.only(topLeft: Radius.circular(28)),

                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: const Color(0xFFF5F8F5),
                    child: _buildMainContent(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ========================================
  // STAFF SIDEBAR
  // ========================================

  Widget _buildSidebar({required bool isMobile}) {
    return Container(
      width: 250,
      color: AppColors.primaryGreen,

      child: SafeArea(
        child: Column(
          children: [
            // ========================================
            // AIDTRACK LOGO AND NAME
            // ========================================

            Padding(
              padding: const EdgeInsets.all(20),

              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
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

            // ========================================
            // STAFF NAVIGATION MENU
            // ========================================
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight;

                  final double itemHeight = (availableHeight / menuItems.length)
                      .clamp(48.0, double.infinity)
                      .toDouble();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),

                    itemCount: menuItems.length,
                    itemExtent: itemHeight,

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

                              // Close drawer on mobile.
                              if (isMobile) {
                                Navigator.pop(context);
                              }

                              // Refresh dashboard data.
                              if (title == 'Dashboard') {
                                _loadDashboard();
                                _loadStaffProfile();
                              }
                            },

                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),

                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    size: 21,

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
                  );
                },
              ),
            ),

            // ========================================
            // STAFF ACCOUNT INFORMATION
            // ========================================
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

                  // ========================================
                  // LOG OUT BUTTON
                  // ========================================
                  SizedBox(
                    width: double.infinity,

                    child: OutlinedButton.icon(
                      onPressed: () async {
                        // Ask for confirmation before logging out.
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
                                      // CANCEL: Stay logged in.
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

                                      // LOG OUT: Confirm logout.
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

                        // Do nothing when the user cancels.
                        if (!mounted || shouldLogout != true) return;

                        // Clear the existing authentication session.
                        AuthService.logout();

                        // Preserve the existing optional logout callback.
                        if (widget.onLogout != null) {
                          widget.onLogout!();
                          return;
                        }

                        // Return to Login and remove the previous page history.
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

  // ========================================
  // MAIN STAFF CONTENT
  // ========================================

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shared yellow page header design.
          _buildPageHeader(),

          // Main page content.
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 22, 25, 25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display selected staff page.
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
                  const StaffReportScreen()
                else if (selectedPage == 'Settings')
                  const StaffSettings(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // AIDTRACK PAGE HEADER
  // ========================================

  Widget _buildPageHeader() {
    final bool isCompact = MediaQuery.of(context).size.width < 600;

    return Container(
      width: double.infinity,
      height: 118,
      padding: const EdgeInsets.symmetric(horizontal: 25),
      decoration: const BoxDecoration(color: AppColors.accentYellow),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedPage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isCompact ? 22 : 27,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),

                const SizedBox(height: 5),

                const Text(
                  'Humanitarian Aid Distribution Management System',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.greyText, fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          const Icon(
            Icons.account_balance_outlined,
            color: AppColors.primaryGreen,
            size: 30,
          ),
        ],
      ),
    );
  }

  // ========================================
  // STAFF DASHBOARD OVERVIEW
  // ========================================

  Widget _buildDashboardOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const Text(
          'Welcome, LGU Staff',

          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Manage household registration, assessments, beneficiaries, and aid distribution.',

          style: TextStyle(fontSize: 13, color: AppColors.greyText),
        ),

        const SizedBox(height: 25),

        // ========================================
        // REFRESH DASHBOARD
        // ========================================
        Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: _dashboardLoading ? null : _refreshDashboardWithFeedback,

              borderRadius: BorderRadius.circular(24),

              // Light gray background ONLY on hover.
              hoverColor: const Color(0xFFE5E7EB),

              // Remove unwanted black/dark effects.
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              focusColor: Colors.transparent,

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_dashboardLoading)
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
                      _dashboardLoading ? 'Refreshing...' : 'Refresh totals',
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
          ),
        ),

        // ========================================
        // DASHBOARD ERROR
        // ========================================
        if (_dashboardError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),

            child: Text(
              _dashboardError!,

              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),

        const SizedBox(height: 8),

        // ========================================
        // SUMMARY CARDS
        // ========================================
        LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;

            final int columns = width >= 1050
                ? 4
                : width >= 550
                ? 2
                : 1;

            final double cardWidth = (width - (columns - 1) * 16) / columns;

            String display(int? value) {
              if (_dashboardLoading) return '…';

              return value?.toString() ?? '—';
            }

            return Wrap(
              spacing: 16,
              runSpacing: 16,

              children: [
                // TOTAL HOUSEHOLDS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Households',
                  icon: Icons.home_outlined,
                  value: display(_totalHouseholds),
                ),

                // TOTAL POPULATION
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Household Population',
                  icon: Icons.people_outline,
                  value: display(_totalPopulation),
                ),

                // ASSESSED HOUSEHOLDS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Assessed Households',
                  icon: Icons.assignment_turned_in_outlined,
                  value: display(_assessedHouseholds),
                ),

                // CLASSIFIED HOUSEHOLDS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Classified Households',
                  icon: Icons.analytics_outlined,
                  value: display(_classifiedHouseholds),
                ),

                // HIGH VULNERABILITY
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'High Vulnerability',
                  icon: Icons.warning_amber_outlined,
                  value: display(_highVulnerability),
                ),

                // AID DISTRIBUTIONS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Distribution Simulations',
                  icon: Icons.inventory_2_outlined,
                  value: display(_aidDistributions),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 25),

        // ========================================
        // HOUSEHOLD VULNERABILITY OVERVIEW
        // ========================================
        _buildDashboardPanel(
          title: 'Household Vulnerability Overview',
          icon: Icons.analytics_outlined,

          child: _buildVulnerabilityOverview(),
        ),

        const SizedBox(height: 20),

        // ========================================
        // RECENT STAFF ACTIVITY
        // ========================================
        _buildDashboardPanel(
          title: 'Recent Activity',
          icon: Icons.history,

          child: _buildRecentActivity(),
        ),

        const SizedBox(height: 25),

        // ========================================
        // FOOTER
        // ========================================
        const Center(
          child: Text(
            'Local Government Unit • Authorized Personnel Only',

            textAlign: TextAlign.center,

            style: TextStyle(fontSize: 11, color: AppColors.greyText),
          ),
        ),
      ],
    );
  }

  // ========================================
  // VULNERABILITY OVERVIEW
  // ========================================

  Widget _buildVulnerabilityOverview() {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(35),

        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    final int total = _classifiedHouseholds ?? 0;

    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.all(35),

        child: Center(
          child: Text(
            'No classification data available yet.',

            style: TextStyle(color: AppColors.greyText, fontSize: 13),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          'Latest vulnerability classification per household ($total households)',

          style: const TextStyle(color: AppColors.greyText, fontSize: 12),
        ),

        const SizedBox(height: 25),

        // LOW VULNERABILITY
        _buildVulnerabilityBar(
          label: 'Low Vulnerability',
          count: _lowVulnerability ?? 0,
          total: total,
          color: AppColors.primaryGreen,
        ),

        const SizedBox(height: 22),

        // MEDIUM VULNERABILITY
        _buildVulnerabilityBar(
          label: 'Medium Vulnerability',
          count: _mediumVulnerability ?? 0,
          total: total,
          color: const Color(0xFFD69A19),
        ),

        const SizedBox(height: 22),

        // HIGH VULNERABILITY
        _buildVulnerabilityBar(
          label: 'High Vulnerability',
          count: _highVulnerability ?? 0,
          total: total,
          color: const Color(0xFFC62828),
        ),

        const SizedBox(height: 18),

        const Text(
          'Model predictions should be reviewed by authorized LGU personnel before aid decisions.',

          style: TextStyle(fontSize: 11, color: AppColors.greyText),
        ),
      ],
    );
  }

  // ========================================
  // VULNERABILITY PROGRESS BAR
  // ========================================

  Widget _buildVulnerabilityBar({
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final double percentage = total == 0
        ? 0.0
        : (count / total).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,

                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
            ),

            Text(
              '$count (${(percentage * 100).toStringAsFixed(1)}%)',

              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),

        const SizedBox(height: 9),

        ClipRRect(
          borderRadius: BorderRadius.circular(20),

          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 11,
            backgroundColor: const Color(0xFFE8EEE9),
            color: color,
          ),
        ),
      ],
    );
  }

  // ========================================
  // RECENT ACTIVITY
  // ========================================

  Widget _buildRecentActivity() {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(30),

        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
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

  // ========================================
  // ACTIVITY ICON
  // ========================================

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

  // ========================================
  // ACTIVITY DATE FORMAT
  // ========================================

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

  // ========================================
  // SUMMARY CARD DESIGN
  // ========================================

  Widget _buildSummaryCard({
    required double width,
    required String title,
    required IconData icon,
    String value = '—',
  }) {
    return Container(
      width: width,
      height: 155,

      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

      decoration: BoxDecoration(
        color: AppColors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE4EBE5)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Icon(icon, color: AppColors.primaryGreen, size: 25),

          const Spacer(),

          Text(
            value,

            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            title,

            style: const TextStyle(fontSize: 13, color: AppColors.greyText),
          ),
        ],
      ),
    );
  }

  // ========================================
  // DASHBOARD PANEL DESIGN
  // ========================================

  Widget _buildDashboardPanel({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(22),

      decoration: BoxDecoration(
        color: AppColors.white,

        borderRadius: BorderRadius.circular(18),

        border: Border.all(color: const Color(0xFFE4EBE5)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryGreen),

              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  title,

                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }
}
