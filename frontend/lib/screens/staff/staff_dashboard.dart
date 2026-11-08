import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../../services/auth_service.dart';

// Household Registration form and records.
import '../households/household_registration.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'staff_settings.dart';
import '../assessment/household_assessment.dart';
import '../vulnerability_classification/vulnerability_classification.dart';

// ========================================
// STAFF DASHBOARD
// ========================================

class StaffDashboard extends StatefulWidget {
  final VoidCallback? onLogout;

  const StaffDashboard({
    super.key,
    this.onLogout,
  });

  @override
  State<StaffDashboard> createState() =>
      _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {

  // Currently selected staff page
  String selectedPage = 'Dashboard';

  // Account name shown in the sidebar.
  String _staffName = 'LGU Staff';

  // Read the currently logged-in account.
  Future<void> _loadStaffProfile() async {
    try {
      final token = AuthService.accessToken;

      if (token == null || token.isEmpty) return;

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/auth/me'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted || response.statusCode != 200) return;

      // Ignore the response if the app session has changed.
      if (AuthService.accessToken != token) return;

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic>) return;

      final name = data['full_name'];

      if (name is! String || name.trim().isEmpty) return;

      setState(() {
        _staffName = name.trim();
      });
    } catch (_) {
      // Keep the role label if the profile request fails.
      // The Settings page provides profile errors and a Refresh button.
    }
  }

  // Dashboard totals loaded from the backend.
  int? _totalHouseholds;
  int? _totalPopulation;

  bool _dashboardLoading = false;
  String? _dashboardError;

  // Only the latest request may update the dashboard.
  int _dashboardRequestId = 0;

  @override
  void initState() {
    super.initState();

    // Load household totals and the logged-in user's name.
    _loadDashboard();
    _loadStaffProfile();
  }

  // Fetch the totals using the currently signed-in user's token.
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

      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/dashboard/summary'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw const AuthException(
          'Your session has expired. Please log out and log in again.',
        );
      }

      if (response.statusCode == 403) {
        throw const AuthException(
          'Your account cannot access the dashboard.',
        );
      }

      if (response.statusCode != 200) {
        throw const AuthException(
          'Unable to load dashboard totals. Please try again.',
        );
      }

      final data = jsonDecode(response.body);

      // Check the response instead of displaying incorrect zero totals.
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
  // STAFF SIDEBAR MENU ITEMS
  // ========================================

  final List<Map<String, dynamic>> menuItems = [
    {
      'title': 'Dashboard',
      'icon': Icons.dashboard_outlined,
    },
    {
      'title': 'Household Registration',
      'icon': Icons.home_outlined,
    },
    {
      'title': 'Household Assessment',
      'icon': Icons.assignment_outlined,
    },
    {
      'title': 'Vulnerability Classification',
      'icon': Icons.analytics_outlined,
    },
    {
      'title': 'Beneficiary Management',
      'icon': Icons.people_outline,
    },
    {
      'title': 'Aid Distribution',
      'icon': Icons.inventory_2_outlined,
    },
    {
      'title': 'Reports',
      'icon': Icons.bar_chart_outlined,
    },
    {
      'title': 'Settings',
      'icon': Icons.settings_outlined,
    },
  ];

  // ========================================
  // RESPONSIVE STAFF DASHBOARD
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
              ? Drawer(
                  child: _buildSidebar(
                    isMobile: true,
                  ),
                )
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
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        TextSpan(
                          text: 'Track',
                          style: TextStyle(
                            color: AppColors.accentYellow,
                          ),
                        ),
                      ],
                    ),

                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : null,

          // ========================================
          // MAIN DASHBOARD LAYOUT
          // ========================================

          body: Row(
            children: [

              // Desktop sidebar
              if (!isMobile)
                _buildSidebar(
                  isMobile: false,
                ),

              // ========================================
              // RIGHT STAFF PANEL
              // ========================================

              Expanded(
                child: ClipRRect(

                  // Keep only the top-left corner curved
                  borderRadius: isMobile
                      ? BorderRadius.zero
                      : const BorderRadius.only(
                          topLeft: Radius.circular(28),
                        ),

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

  Widget _buildSidebar({
    required bool isMobile,
  }) {
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

                  // White rounded logo container
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

                  // AidTrack text beside logo
                  const Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [

                          // Aid stays white
                          TextSpan(
                            text: 'Aid',
                            style: TextStyle(
                              color: AppColors.white,
                            ),
                          ),

                          // Track stays yellow
                          TextSpan(
                            text: 'Track',
                            style: TextStyle(
                              color: AppColors.accentYellow,
                            ),
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

            const Divider(
              color: Colors.white24,
            ),

            const SizedBox(height: 4),

            // ========================================
            // STAFF NAVIGATION MENU
            // ========================================

            // Fill the available menu height with evenly sized items.
            // On shorter screens, allow scrolling instead of cutting off Settings.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight;

                  // Each item gets an equal share, with enough room for long labels.
                  final itemHeight =
                      (availableHeight / menuItems.length).clamp(48.0, double.infinity);

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
                            // Remove the gray click effect; preserve the default hover shadow.
                            splashFactory: NoSplash.splashFactory,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,

                            onTap: () {
                              setState(() {
                                selectedPage = title;
                              });

                              // Close the drawer when using the mobile layout.
                              if (isMobile) {
                                Navigator.pop(context);
                              }

                              // Reload dashboard totals and account name.
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

            const Divider(
              color: Colors.white24,
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 10,
              ),

              child: Column(
                children: [

                  // Display the logged-in Staff's name and role.
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
                            // Hover to read the complete name when it is long.
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
                      onPressed: () {

                        // Clear the saved token
                        AuthService.logout();

                        // Use custom logout function if provided
                        if (widget.onLogout != null) {
                          widget.onLogout!();
                          return;
                        }

                        // Return to login and remove previous screens
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) =>
                                const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },

                      icon: const Icon(
                        Icons.logout,
                        size: 18,
                      ),

                      label: const Text(
                        'Log Out',

                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.white,

                        side: const BorderSide(
                          color: Colors.white54,
                        ),

                        padding:
                            const EdgeInsets.symmetric(
                          vertical: 12,
                        ),

                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(10),
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
      padding: const EdgeInsets.all(25),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // ========================================
          // PAGE HEADER
          // ========================================

          Row(
            children: [

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(
                      selectedPage,

                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                    ),

                    const SizedBox(height: 5),

                    const Text(
                      'Humanitarian Aid Distribution Management System',

                      style: TextStyle(
                        color: AppColors.greyText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.account_balance_outlined,
                color: AppColors.primaryGreen,
                size: 30,
              ),
            ],
          ),

          const SizedBox(height: 30),

          // ========================================
          // DISPLAY SELECTED STAFF PAGE
          // ========================================

          if (selectedPage == 'Dashboard')
            _buildDashboardOverview()

          // Display the connected Household Registration screen.
          else if (selectedPage == 'Household Registration')
            const HouseholdRegistration()

          else if (selectedPage == 'Household Assessment')
            const HouseholdAssessmentScreen()

          else if (selectedPage == 'Vulnerability Classification')
            const VulnerabilityClassificationScreen()

          else if (selectedPage ==
              'Beneficiary Management')
            _buildModulePlaceholder(
              title: 'Beneficiary Management',
              icon: Icons.people_outline,
              message:
                  'Beneficiary records and management will be developed in this module.',
            )

          else if (selectedPage ==
              'Aid Distribution')
            _buildModulePlaceholder(
              title: 'Aid Distribution',
              icon: Icons.inventory_2_outlined,
              message:
                  'Aid distribution recording and history will be developed in this module.',
            )

          else if (selectedPage == 'Reports')
            _buildModulePlaceholder(
              title: 'Reports',
              icon: Icons.bar_chart_outlined,
              message:
                  'Staff reports will be developed in this module.',
            )
          else if (selectedPage == 'Settings')
            const StaffSettings(),
        ],
      ),
    );
  }

  // ========================================
  // STAFF DASHBOARD OVERVIEW
  // ========================================

  Widget _buildDashboardOverview() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

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

          style: TextStyle(
            fontSize: 13,
            color: AppColors.greyText,
          ),
        ),

        const SizedBox(height: 25),

        // ========================================
        // STAFF SUMMARY CARDS
        // ========================================
        // Manually reload the latest household totals.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _dashboardLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
            label: Text(
              _dashboardLoading ? 'Loading...' : 'Refresh totals',
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
            ),
          ),
        ),

        // Show request errors above the cards.
        if (_dashboardError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _dashboardError!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
              ),
            ),
          ),

        const SizedBox(height: 8),

        LayoutBuilder(
          builder: (context, constraints) {

            final double width =
                constraints.maxWidth;

            // 4 cards on large desktop
            // 2 cards on medium screens
            // 1 card on small screens
            final int columns =
                width >= 1050
                    ? 4
                    : width >= 550
                        ? 2
                        : 1;

            final double cardWidth =
                (width -
                    (columns - 1) * 16) /
                    columns;

            return Wrap(
              spacing: 16,
              runSpacing: 16,

              children: [
                
                // Number of household records registered in AidTrack.
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Households',
                  icon: Icons.home_outlined,
                  value: _dashboardLoading
                      ? '…'
                      : (_totalHouseholds?.toString() ?? '—'),
                ),

                // Total people in registered households, including household heads.
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Household Population',
                  icon: Icons.people_outline,
                  value: _dashboardLoading
                      ? '…'
                      : (_totalPopulation?.toString() ?? '—'),
                ),

                // Completed assessments
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Assessed Households',
                  icon:
                      Icons.assignment_turned_in_outlined,
                ),

                // High vulnerability households
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'High Vulnerability',
                  icon:
                      Icons.warning_amber_outlined,
                ),

                // Aid distributions recorded
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Aid Distributions',
                  icon:
                      Icons.inventory_2_outlined,
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 25),

        // ========================================
        // VULNERABILITY OVERVIEW
        // ========================================

        _buildDashboardPanel(
          title:
              'Household Vulnerability Overview',

          icon:
              Icons.analytics_outlined,

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

                style: TextStyle(
                  color: AppColors.greyText,
                  fontSize: 13,
                ),
              ),

              SizedBox(height: 35),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ========================================
        // RECENT STAFF ACTIVITY
        // ========================================

        _buildDashboardPanel(
          title: 'Recent Activity',
          icon: Icons.history,

          child: const Padding(
            padding: EdgeInsets.symmetric(
              vertical: 35,
            ),

            child: Center(
              child: Text(
                'No recent activity available yet.',

                style: TextStyle(
                  color: AppColors.greyText,
                  fontSize: 13,
                ),
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

            style: TextStyle(
              fontSize: 11,
              color: AppColors.greyText,
            ),
          ),
        ),
      ],
    );
  }

  // ========================================
  // STAFF MODULE PLACEHOLDER
  // ========================================

  Widget _buildModulePlaceholder({
    required String title,
    required IconData icon,
    required String message,
  }) {
    return _buildDashboardPanel(
      title: title,
      icon: icon,

      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 40,
        ),

        child: Center(
          child: Text(
            message,

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: AppColors.greyText,
              fontSize: 14,
            ),
          ),
        ),
      ),
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

      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),

      decoration: BoxDecoration(
        color: AppColors.white,

        borderRadius:
            BorderRadius.circular(18),

        border: Border.all(
          color:
              const Color(0xFFE4EBE5),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          Icon(
            icon,
            color: AppColors.primaryGreen,
            size: 25,
          ),

          const Spacer(),

          // Display the supplied total or a placeholder for pending modules.
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

            style: const TextStyle(
              fontSize: 13,
              color: AppColors.greyText,
            ),
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

        borderRadius:
            BorderRadius.circular(18),

        border: Border.all(
          color:
              const Color(0xFFE4EBE5),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          Row(
            children: [

              Icon(
                icon,
                color: AppColors.primaryGreen,
              ),

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