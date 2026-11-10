import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../../services/auth_service.dart';
import 'user_management.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../households/household_registration.dart';
import '../reports/staff_report.dart';
import 'admin_settings.dart';

// ========================================
// ADMIN DASHBOARD
// ========================================

class AdminDashboard extends StatefulWidget {
  final VoidCallback? onLogout;

  const AdminDashboard({super.key, this.onLogout});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Currently selected administrator page
  String selectedPage = 'Dashboard';

  // Profile details of the currently logged-in administrator.
  String _adminName = 'Loading...';
  String _adminRole = 'LGU Administrator';

  // Household totals fetched from the backend.
  int? _totalHouseholds;
  int? _totalPopulation;

  int? _assessedHouseholds;
  int? _classifiedHouseholds;
  int? _highVulnerability;
  int? _simulatedDistributions;
  int? _lowVulnerability;
  int? _mediumVulnerability;

  List<Map<String, dynamic>> _recentActivity = [];

  // Loading and error messages for the dashboard.
  bool _dashboardLoading = false;
  String? _dashboardError;

  // Prevent an older request from replacing newer results.
  int _dashboardRequestId = 0;

  @override
  void initState() {
    super.initState();

    // Load dashboard totals and the current account's profile.
    _loadDashboard();
    _loadAdminProfile();
  }

  // Fetch the account identified by the current login token.
  Future<void> _loadAdminProfile() async {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      setState(() {
        _adminName = 'Profile unavailable';
      });
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/auth/me'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw const FormatException('Unable to load profile.');
      }

      final data = jsonDecode(response.body);

      // Check the profile before displaying it.
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid profile response.');
      }

      final name = data['full_name'];
      final role = data['role'];

      if (name is! String ||
          name.trim().isEmpty ||
          role is! String ||
          role.trim().isEmpty) {
        throw const FormatException('Missing profile details.');
      }

      // Ignore the response if the user has left or changed sessions.
      if (!mounted || AuthService.accessToken != token) return;

      setState(() {
        _adminName = name.trim();
        _adminRole = role == 'Admin' ? 'LGU Administrator' : role;
      });
    } catch (_) {
      if (!mounted || AuthService.accessToken != token) return;

      setState(() {
        _adminName = 'Profile unavailable';
      });
    }
  }

  // Read the household totals using the Admin's login token.
  Future<void> _loadDashboard() async {
    final requestId = ++_dashboardRequestId;

    setState(() {
      _dashboardLoading = true;
      _dashboardError = null;
      _totalHouseholds = null;
      _totalPopulation = null;
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
        throw const AuthException(
          'Your account cannot access dashboard totals.',
        );
      }

      if (response.statusCode != 200) {
        throw const AuthException(
          'Unable to load dashboard totals. Please try again.',
        );
      }

      final data = jsonDecode(response.body);

      // Validate the response before displaying the totals.
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Invalid dashboard response.');
      }

      // Validate the dashboard statistics.
      const requiredFields = [
        'total_households',
        'total_population',
        'assessed_households',
        'classified_households',
        'high_vulnerability',
        'simulated_distributions',
      ];

      for (final field in requiredFields) {
        final value = data[field];

        if (value is! int || value < 0) {
          throw const FormatException('Invalid dashboard statistics.');
        }
      }

      final households = data['total_households'] as int;
      final population = data['total_population'] as int;
      final assessed = data['assessed_households'] as int;
      final classified = data['classified_households'] as int;
      final high = data['high_vulnerability'] as int;
      final low = data['low_vulnerability'];
      final medium = data['medium_vulnerability'];
      final recent = data['recent_activity'];

      if (low is! int ||
          low < 0 ||
          medium is! int ||
          medium < 0 ||
          recent is! List) {
        throw const FormatException('Invalid dashboard overview data.');
      }

      final activities = recent.map<Map<String, dynamic>>((item) {
        if (item is! Map) {
          throw const FormatException('Invalid recent activity.');
        }

        final activity = Map<String, dynamic>.from(item);

        if (activity['activity_type'] is! String ||
            activity['description'] is! String ||
            activity['occurred_at'] is! String) {
          throw const FormatException('Incomplete activity record.');
        }

        return activity;
      }).toList();

      final simulated = data['simulated_distributions'] as int;

      // Ignore results if the screen closed or a newer request started.
      if (!mounted || requestId != _dashboardRequestId) return;

      setState(() {
        _totalHouseholds = households;
        _totalPopulation = population;
        _assessedHouseholds = assessed;
        _classifiedHouseholds = classified;
        _highVulnerability = high;
        _simulatedDistributions = simulated;
        _lowVulnerability = low;
        _mediumVulnerability = medium;
        _recentActivity = activities;
      });
    } catch (error) {
      if (!mounted || requestId != _dashboardRequestId) return;

      final String message;

      if (error is AuthException) {
        message = error.message;
      } else if (error is TimeoutException) {
        message = 'The server took too long. Please try again.';
      } else if (error is http.ClientException) {
        message = 'Cannot connect to the server. Check your connection.';
      } else {
        message = 'Unable to read dashboard totals. Please try again.';
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
  // ADMIN SIDEBAR MENU ITEMS
  // ========================================

  final List<Map<String, dynamic>> menuItems = [
    {'title': 'Dashboard', 'icon': Icons.dashboard_outlined},
    {'title': 'Household Records', 'icon': Icons.home_outlined},
    {'title': 'Reports', 'icon': Icons.bar_chart_outlined},
    {'title': 'User Management', 'icon': Icons.manage_accounts_outlined},
    {'title': 'Settings', 'icon': Icons.settings_outlined},
  ];

  // ========================================
  // RESPONSIVE ADMIN DASHBOARD
  // ========================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use mobile layout below 900 pixels
        final isMobile = constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: AppColors.primaryGreen,

          // Mobile sidebar drawer
          drawer: isMobile
              ? Drawer(child: _buildSidebar(isMobile: true))
              : null,

          // Mobile top navigation bar
          appBar: isMobile
              ? AppBar(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.primaryGreen,
                  leadingWidth: 52,
                  titleSpacing: 0,

                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/aidtrack_symbol.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                      ),

                      const SizedBox(width: 8),

                      const Text.rich(
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
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : null,

          // ========================================
          // MAIN DASHBOARD LAYOUT
          // ========================================
          body: Row(
            children: [
              // Desktop sidebar
              if (!isMobile) _buildSidebar(isMobile: false),

              // ========================================
              // RIGHT ADMIN PANEL
              // ========================================
              Expanded(
                child: ClipRRect(
                  // Keep only the top-left corner curved
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
  // ADMIN SIDEBAR
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

                  // ========================================
                  // AIDTRACK TEXT BESIDE THE LOGO
                  // ========================================
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

            const SizedBox(height: 15),

            // ========================================
            // ADMIN NAVIGATION MENU
            // ========================================
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: menuItems.length,

                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final String title = item['title'];
                  final bool isSelected = selectedPage == title;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),

                    // Paint the selected yellow background on the Material itself.
                    child: Material(
                      color: isSelected
                          ? AppColors.accentYellow
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,

                      child: InkWell(
                        // Keep the default hover shadow, just like Staff.
                        // Remove only the click splash and pressed highlight.
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,

                        onTap: () {
                          setState(() {
                            selectedPage = title;
                          });

                          // Close the sidebar drawer on mobile.
                          if (isMobile) {
                            Navigator.pop(context);
                          }

                          // Refresh dashboard totals.
                          if (title == 'Dashboard') {
                            _loadDashboard();
                          }
                        },

                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),

                          child: Row(
                            children: [
                              // Module icon.
                              Icon(
                                item['icon'],
                                size: 21,
                                color: isSelected
                                    ? AppColors.primaryGreen
                                    : Colors.white70,
                              ),

                              const SizedBox(width: 12),

                              // Module name stays visible when selected.
                              Expanded(
                                child: Text(
                                  title,
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

            // ========================================
            // ADMIN ACCOUNT INFORMATION
            // ========================================
            const Divider(color: Colors.white24),

            Padding(
              padding: const EdgeInsets.all(15),

              child: Column(
                children: [
                  Row(
                    children: [
                      // Account profile icon.
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
                            // Display the actual name saved in the database.
                            // Hover over it to see the full name if it is long.
                            Tooltip(
                              message: _adminName,
                              child: Text(
                                _adminName,
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

                            // Display the account's role below the name.
                            Text(
                              _adminRole,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),

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
                                      // Cancel: stay logged in.
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

                                      // Confirm: proceed with logout.
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

                        // Cancel means no logout.
                        if (!mounted || shouldLogout != true) return;

                        // Clear the session only after confirmation.
                        AuthService.logout();

                        // Preserve your existing custom logout behavior.
                        if (widget.onLogout != null) {
                          widget.onLogout!();
                          return;
                        }

                        // Return to Login Screen and clear navigation history.
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
  // MAIN ADMIN CONTENT
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
                // Display selected administrator page.
                if (selectedPage == 'Dashboard')
                  _buildDashboardOverview()
                else if (selectedPage == 'Household Records')
                  const HouseholdRegistration(readOnly: true)
                else if (selectedPage == 'Reports')
                  const StaffReportScreen(heading: 'Admin Reports')
                else if (selectedPage == 'User Management')
                  const UserManagement()
                else if (selectedPage == 'Settings')
                  const AdminSettings(),
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
  // ADMIN DASHBOARD OVERVIEW
  // ========================================

  Widget _buildDashboardOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const Text(
          'Welcome, LGU Administrator',

          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Monitor household records, vulnerability classifications, and aid distribution.',

          style: TextStyle(fontSize: 13, color: AppColors.greyText),
        ),

        const SizedBox(height: 25),

        // ========================================
        // ADMIN MONITORING SUMMARY CARDS
        // ========================================

        // Reload totals after staff register, edit, or delete households.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _dashboardLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
            label: Text(_dashboardLoading ? 'Loading...' : 'Refresh totals'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
            ),
          ),
        ),

        // Display errors above the summary cards.
        if (_dashboardError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _dashboardError!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),

        const SizedBox(height: 8),

        LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;

            // 4 cards for large desktop
            // 2 cards for medium screens
            // 1 card for small screens
            final int columns = width >= 1050
                ? 4
                : width >= 550
                ? 2
                : 1;

            final double cardWidth = (width - (columns - 1) * 16) / columns;

            return Wrap(
              spacing: 16,
              runSpacing: 16,

              children: [
                // Total household records registered in AidTrack.
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Households',
                  icon: Icons.home_outlined,
                  value: _dashboardLoading
                      ? '…'
                      : (_totalHouseholds?.toString() ?? '—'),
                ),

                // Total people in registered households, including the heads.
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Household Population',
                  icon: Icons.people_outline,
                  value: _dashboardLoading
                      ? '…'
                      : (_totalPopulation?.toString() ?? '—'),
                ),

                // ASSESSED HOUSEHOLDS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Assessed Households',
                  icon: Icons.assignment_turned_in_outlined,
                  value: _dashboardLoading
                      ? '…'
                      : (_assessedHouseholds?.toString() ?? '—'),
                ),

                // CLASSIFIED HOUSEHOLDS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Classified Households',
                  icon: Icons.analytics_outlined,
                  value: _dashboardLoading
                      ? '…'
                      : (_classifiedHouseholds?.toString() ?? '—'),
                ),

                // HIGH VULNERABILITY
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'High Vulnerability',
                  icon: Icons.warning_amber_outlined,
                  value: _dashboardLoading
                      ? '…'
                      : (_highVulnerability?.toString() ?? '—'),
                ),

                // DISTRIBUTION SIMULATIONS
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Distribution Simulations',
                  icon: Icons.inventory_2_outlined,
                  value: _dashboardLoading
                      ? '…'
                      : (_simulatedDistributions?.toString() ?? '—'),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 25),

        // ========================================
        // VULNERABILITY MONITORING
        // ========================================
        _buildDashboardPanel(
          title: 'Household Vulnerability Overview',
          icon: Icons.analytics_outlined,
          child: _buildAdminVulnerabilityOverview(),
        ),

        const SizedBox(height: 20),

        // ========================================
        // RECENT SYSTEM ACTIVITY
        // ========================================
        _buildDashboardPanel(
          title: 'Recent Activity',
          icon: Icons.history,
          child: _buildAdminRecentActivity(),
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
  // ADMIN HOUSEHOLD VULNERABILITY OVERVIEW
  // ========================================

  Widget _buildAdminVulnerabilityOverview() {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(35),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    final total = _classifiedHouseholds ?? 0;

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

        _adminVulnerabilityBar(
          label: 'Low Vulnerability',
          count: _lowVulnerability ?? 0,
          total: total,
          color: AppColors.primaryGreen,
        ),

        const SizedBox(height: 22),

        _adminVulnerabilityBar(
          label: 'Medium Vulnerability',
          count: _mediumVulnerability ?? 0,
          total: total,
          color: const Color(0xFFD69A19),
        ),

        const SizedBox(height: 22),

        _adminVulnerabilityBar(
          label: 'High Vulnerability',
          count: _highVulnerability ?? 0,
          total: total,
          color: const Color(0xFFC62828),
        ),

        const SizedBox(height: 18),

        const Text(
          'Predictions use synthetic training data and require validation before official LGU decisions.',
          style: TextStyle(fontSize: 11, color: AppColors.greyText),
        ),
      ],
    );
  }

  // ========================================
  // VULNERABILITY PROGRESS BAR
  // ========================================

  Widget _adminVulnerabilityBar({
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final percentage = total == 0
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
  // ADMIN RECENT ACTIVITY
  // ========================================

  Widget _buildAdminRecentActivity() {
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
            style: TextStyle(fontSize: 13, color: AppColors.greyText),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(_recentActivity.length, (index) {
        final activity = _recentActivity[index];
        final type = activity['activity_type'] as String;
        final description = activity['description'] as String;
        final occurredAt = activity['occurred_at'] as String;

        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.lightGreen,
                child: Icon(
                  _adminActivityIcon(type),
                  color: AppColors.primaryGreen,
                ),
              ),
              title: Text(
                type,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(description, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(
                      _adminActivityDate(occurredAt),
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
  // ADMIN ACTIVITY ICON
  // ========================================

  IconData _adminActivityIcon(String type) {
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
  // ADMIN ACTIVITY DATE
  // ========================================

  String _adminActivityDate(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return value;

    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${date.year}-${twoDigits(date.month)}-'
        '${twoDigits(date.day)} '
        '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
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

      padding: const EdgeInsets.all(20),

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

          // Display the fetched total or a placeholder.
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
