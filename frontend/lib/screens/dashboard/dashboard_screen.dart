
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// ========================================
// USER ROLES
// ========================================

enum UserRole {
  administrator,
  staff,
}

// ========================================
// DASHBOARD SCREEN
// ========================================

class DashboardScreen extends StatefulWidget {
  final UserRole role;
  final VoidCallback? onLogout;

  const DashboardScreen({
    super.key,
    required this.role,
    this.onLogout,
  });

  @override
  State<DashboardScreen> createState() =>
      _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  // Currently selected sidebar page
  String selectedPage = 'Dashboard';

  // Check if the logged-in user is an administrator
  bool get isAdmin =>
      widget.role == UserRole.administrator;

  // ========================================
  // SIDEBAR MENU ITEMS
  // ========================================

  List<Map<String, dynamic>> get menuItems => [
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

    // Only the LGU Administrator can see this menu.
    if (isAdmin)
      {
        'title': 'User Management',
        'icon': Icons.manage_accounts_outlined,
      },
  ];

  // ========================================
  // RESPONSIVE DASHBOARD
  // ========================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {

        // Use a mobile layout below 900 pixels
        final isMobile = constraints.maxWidth < 900;

        return Scaffold(
          backgroundColor: AppColors.primaryGreen,

          // Mobile navigation drawer
          drawer: isMobile
              ? Drawer(
                  child: _buildSidebar(isMobile: true),
                )
              : null,

          // Mobile top navigation bar
          appBar: isMobile
              ? AppBar(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.primaryGreen,
                  title: const Text(
                    'AidTrack',
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
                _buildSidebar(isMobile: false),

              // ========================================
              // RIGHT DASHBOARD PANEL
              // ========================================

              Expanded(
                child: ClipRRect(
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
                  ), // Closes Container
                ), // Closes ClipRRect
              ), // Closes Expanded

            ],
          ),
        );
      },
    );
  }

  // ========================================
  // LEFT SIDEBAR
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
            // SYSTEM LOGO
            // ========================================

            Padding(
              padding: const EdgeInsets.all(20),

              child: Row(
                children: [

                  // White rounded container for the original AidTrack logo
                  Container(
                    width: 64,
                    height: 64,

                    padding: const EdgeInsets.all(6),

                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),

                    child: Image.asset(
                      'assets/images/aidtrack_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(width: 10),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        const Text.rich(
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

                        Text(
                          'LGU Management System',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
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
            // NAVIGATION MENU
            // ========================================

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                ),

                itemCount: menuItems.length,

                itemBuilder: (context, index) {
                  final item = menuItems[index];

                  final String title = item['title'];

                  final bool isSelected =
                      selectedPage == title;

                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: 5,
                    ),

                    child: Container(
                      decoration: BoxDecoration(
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

                        onTap: () {

                          setState(() {
                            selectedPage = title;
                          });

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
            // LOGGED-IN USER INFORMATION
            // ========================================

            const Divider(
              color: Colors.white24,
            ),

            Padding(
              padding: const EdgeInsets.all(15),

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
                          crossAxisAlignment:
                              CrossAxisAlignment.start,

                          children: [

                            Text(
                              isAdmin
                                  ? 'LGU Administrator'
                                  : 'LGU Staff',

                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),

                            const Text(
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

                  if (widget.onLogout != null) ...[
                    const SizedBox(height: 15),

                    ListTile(
                      leading: const Icon(
                        Icons.logout,
                        color: Colors.white70,
                      ),

                      title: const Text(
                        'Log Out',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),

                      onTap: widget.onLogout,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // MAIN DASHBOARD CONTENT
  // ========================================

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          // ========================================
          // DASHBOARD HEADER
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
          // DISPLAY SELECTED PAGE
          // ========================================

          if (selectedPage == 'Dashboard')
            _buildDashboardOverview()
          else
            _buildModulePlaceholder(),
        ],
      ),
    );
  }

  // ========================================
  // DASHBOARD OVERVIEW
  // ========================================

  Widget _buildDashboardOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [

        Text(
          isAdmin
              ? 'Welcome, LGU Administrator'
              : 'Welcome, LGU Staff',

          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
          ),
        ),

        const SizedBox(height: 5),

        const Text(
          'Overview of household assessments and aid distribution.',

          style: TextStyle(
            fontSize: 13,
            color: AppColors.greyText,
          ),
        ),

        const SizedBox(height: 25),

        // ========================================
        // SUMMARY CARDS
        // ========================================

        LayoutBuilder(
          builder: (context, constraints) {

            final double width = constraints.maxWidth;

            // Four cards on wide screens
            // Two cards on medium screens
            // One card on small screens

            final int columns = width >= 1050
                ? 4
                : width >= 550
                    ? 2
                    : 1;

            final double cardWidth =
                (width - (columns - 1) * 16) / columns;

            return Wrap(
              spacing: 16,
              runSpacing: 16,

              children: [

                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Households',
                  icon: Icons.home_outlined,
                ),

                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Assessed Households',
                  icon: Icons.assignment_turned_in_outlined,
                ),

                _buildSummaryCard(
                  width: cardWidth,
                  title: 'High Vulnerability',
                  icon: Icons.warning_amber_outlined,
                ),

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
        // VULNERABILITY OVERVIEW
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
        // RECENT ACTIVITY
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

        borderRadius: BorderRadius.circular(18),

        border: Border.all(
          color: const Color(0xFFE4EBE5),
        ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          Icon(
            icon,
            color: AppColors.primaryGreen,
            size: 25,
          ),

          const Spacer(),

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

        borderRadius: BorderRadius.circular(18),

        border: Border.all(
          color: const Color(0xFFE4EBE5),
        ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

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

  // ========================================
  // OTHER MODULES
  // ========================================

  Widget _buildModulePlaceholder() {
    return _buildDashboardPanel(
      title: selectedPage,
      icon: Icons.construction_outlined,

      child: const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 40,
        ),

        child: Center(
          child: Text(
            'This module will be developed in the next stage.',

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
}