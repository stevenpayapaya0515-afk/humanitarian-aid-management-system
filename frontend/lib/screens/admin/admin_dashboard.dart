import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../../services/auth_service.dart';
import 'user_management.dart';

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../households/household_registration.dart';
import 'admin_reports.dart';
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

      final households = data['total_households'];
      final population = data['total_population'];

      if (households is! int || population is! int) {
        throw const FormatException('Invalid dashboard totals.');
      }

      if (households < 0 || population < 0) {
        throw const FormatException('Invalid dashboard totals.');
      }

      // Ignore results if the screen closed or a newer request started.
      if (!mounted || requestId != _dashboardRequestId) return;

      setState(() {
        _totalHouseholds = households;
        _totalPopulation = population;
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
                      onPressed: () {
                        // Clear the token stored in Flutter
                        AuthService.logout();

                        // Use custom logout function if provided
                        if (widget.onLogout != null) {
                          widget.onLogout!();
                          return;
                        }

                        // Return to Login Screen
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
                  const AdminReports()
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
      decoration: const BoxDecoration(
        color: AppColors.accentYellow,
      ),
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

                // Completed household assessments
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Assessed Households',
                  icon: Icons.assignment_turned_in_outlined,
                ),

                // Households classified as high vulnerability
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'High Vulnerability',
                  icon: Icons.warning_amber_outlined,
                ),

                // Recorded aid distribution transactions
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Aid Distributions',
                  icon: Icons.inventory_2_outlined,
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

          child: const Column(
            children: [
              SizedBox(height: 35),

              Icon(
                Icons.bar_chart_outlined,
                size: 48,
                color: AppColors.primaryGreen,
              ),

              SizedBox(height: 15),

              Text(
                'No classification data available yet.',

                textAlign: TextAlign.center,

                style: TextStyle(color: AppColors.greyText, fontSize: 13),
              ),

              SizedBox(height: 35),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ========================================
        // RECENT SYSTEM ACTIVITY
        // ========================================
        _buildDashboardPanel(
          title: 'Recent Activity',
          icon: Icons.history,

          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 35),

            child: Center(
              child: Text(
                'No recent activity available yet.',

                style: TextStyle(color: AppColors.greyText, fontSize: 13),
              ),
            ),
          ),
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
