import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';

// ========================================
// ADMIN DASHBOARD
// ========================================

class AdminDashboard extends StatefulWidget {
  final VoidCallback? onLogout;

  const AdminDashboard({
    super.key,
    this.onLogout,
  });

  @override
  State<AdminDashboard> createState() =>
      _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {

  // Currently selected administrator page
  String selectedPage = 'Dashboard';

  // ========================================
  // ADMIN SIDEBAR MENU ITEMS
  // ========================================

  final List<Map<String, dynamic>> menuItems = [
    {
      'title': 'Dashboard',
      'icon': Icons.dashboard_outlined,
    },
    {
      'title': 'Reports',
      'icon': Icons.bar_chart_outlined,
    },
    {
      'title': 'User Management',
      'icon': Icons.manage_accounts_outlined,
    },
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
              // RIGHT ADMIN PANEL
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
  // ADMIN SIDEBAR
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
                            style: TextStyle(
                              color: AppColors.white,
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

            const SizedBox(height: 15),

            // ========================================
            // ADMIN NAVIGATION MENU
            // ========================================

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),

                itemCount: menuItems.length,

                itemBuilder: (context, index) {

                  final item = menuItems[index];

                  final String title =
                      item['title'];

                  final bool isSelected =
                      selectedPage == title;

                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 5,
                    ),

                    child: Container(
                      decoration: BoxDecoration(

                        // Yellow highlight for selected menu
                        color: isSelected
                            ? AppColors.accentYellow
                            : Colors.transparent,

                        borderRadius:
                            BorderRadius.circular(12),
                      ),

                      child: ListTile(
                        dense: true,

                        leading: Icon(
                          item['icon'],
                          size: 21,

                          color: isSelected
                              ? AppColors.primaryGreen
                              : Colors.white70,
                        ),

                        title: Text(
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

                        // Change selected admin page
                        onTap: () {

                          setState(() {
                            selectedPage = title;
                          });

                          // Close drawer on mobile
                          if (isMobile) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // ========================================
            // ADMIN ACCOUNT INFORMATION
            // ========================================

            const Divider(
              color: Colors.white24,
            ),

            Padding(
              padding: const EdgeInsets.all(15),

              child: Column(
                children: [

                  const Row(
                    children: [

                      // Admin profile icon
                      CircleAvatar(
                        backgroundColor: Colors.white,

                        child: Icon(
                          Icons.person_outline,
                          color: AppColors.primaryGreen,
                        ),
                      ),

                      SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [

                            Text(
                              'LGU Administrator',

                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),

                            Text(
                              'Authorized Personnel',

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

                  const SizedBox(height: 15),

                  // ========================================
                  // LOG OUT BUTTON
                  // ========================================

                  SizedBox(
                    width: double.infinity,

                    child: OutlinedButton.icon(
                      onPressed: () {

                        // Use custom logout function if provided
                        if (widget.onLogout != null) {
                          widget.onLogout!();
                          return;
                        }

                        // Return to Login Screen
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
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

                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),

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
                      'Aid Distribution Management System',

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
          // DISPLAY SELECTED ADMIN PAGE
          // ========================================

          if (selectedPage == 'Dashboard')
            _buildDashboardOverview()
          else if (selectedPage == 'Reports')
            _buildReportsPlaceholder()
          else if (selectedPage == 'User Management')
            _buildUserManagementPlaceholder(),
        ],
      ),
    );
  }

  // ========================================
  // ADMIN DASHBOARD OVERVIEW
  // ========================================

  Widget _buildDashboardOverview() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

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

          style: TextStyle(
            fontSize: 13,
            color: AppColors.greyText,
          ),
        ),

        const SizedBox(height: 25),

        // ========================================
        // ADMIN MONITORING SUMMARY CARDS
        // ========================================

        LayoutBuilder(
          builder: (context, constraints) {

            final double width =
                constraints.maxWidth;

            // 4 cards for large desktop
            // 2 cards for medium screens
            // 1 card for small screens
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

                // Total registered households
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Households',
                  icon: Icons.home_outlined,
                ),

                // Completed household assessments
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Assessed Households',
                  icon:
                      Icons.assignment_turned_in_outlined,
                ),

                // Households classified as high vulnerability
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'High Vulnerability',
                  icon:
                      Icons.warning_amber_outlined,
                ),

                // Recorded aid distribution transactions
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
        // VULNERABILITY MONITORING
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
        // RECENT SYSTEM ACTIVITY
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
  // REPORTS PAGE PLACEHOLDER
  // ========================================

  Widget _buildReportsPlaceholder() {
    return _buildDashboardPanel(
      title: 'Reports',
      icon: Icons.bar_chart_outlined,

      child: const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 40,
        ),

        child: Center(
          child: Text(
            'Administrator reports will be developed in this module.',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: AppColors.greyText,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // USER MANAGEMENT PAGE PLACEHOLDER
  // ========================================

  Widget _buildUserManagementPlaceholder() {
    return _buildDashboardPanel(
      title: 'User Management',
      icon:
          Icons.manage_accounts_outlined,

      child: const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 40,
        ),

        child: Center(
          child: Text(
            'LGU user account management will be developed in this module.',

            textAlign: TextAlign.center,

            style: TextStyle(
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
  }) {
    return Container(
      width: width,
      height: 155,

      padding: const EdgeInsets.all(20),

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

          // Real values will come from backend later
          const Text(
            '—',

            style: TextStyle(
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