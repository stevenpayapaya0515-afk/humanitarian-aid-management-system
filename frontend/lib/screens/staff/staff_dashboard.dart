import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';

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

            const SizedBox(height: 15),

            // ========================================
            // STAFF NAVIGATION MENU
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

                        // Change selected staff page
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
            // STAFF ACCOUNT INFORMATION
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

                      // Staff profile icon
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
                              'LGU Staff',

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
                            builder: (context) =>
                                const LoginScreen(),
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
          // DISPLAY SELECTED STAFF PAGE
          // ========================================

          if (selectedPage == 'Dashboard')
            _buildDashboardOverview()

          else if (selectedPage ==
              'Household Registration')
            _buildModulePlaceholder(
              title: 'Household Registration',
              icon: Icons.home_outlined,
              message:
                  'Household registration form and records will be developed in this module.',
            )

          else if (selectedPage ==
              'Household Assessment')
            _buildModulePlaceholder(
              title: 'Household Assessment',
              icon: Icons.assignment_outlined,
              message:
                  'Household assessment form and records will be developed in this module.',
            )

          else if (selectedPage ==
              'Vulnerability Classification')
            _buildModulePlaceholder(
              title: 'Vulnerability Classification',
              icon: Icons.analytics_outlined,
              message:
                  'Machine learning vulnerability results will be displayed in this module.',
            )

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

                // Total registered households
                _buildSummaryCard(
                  width: cardWidth,
                  title: 'Total Households',
                  icon: Icons.home_outlined,
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

          // Real data will come from backend later
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