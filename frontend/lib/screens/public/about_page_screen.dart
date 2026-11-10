import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ========================================
// AIDTRACK PUBLIC ABOUT PAGE
// ========================================

class AboutPageScreen extends StatelessWidget {
  const AboutPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      backgroundColor: AppColors.primaryGreen,

      // ========================================
      // TOP NAVIGATION
      // ========================================
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primaryGreen,
        elevation: 0,
        toolbarHeight: 72,
        leadingWidth: 48,
        titleSpacing: 0,

        // Keep the default back arrow.
        automaticallyImplyLeading: true,

        // AidTrack logo and name beside the back arrow.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/aidtrack_symbol.png',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),

            const SizedBox(width: 8),

            const Text(
              'AidTrack',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
          ],
        ),
      ),

      // ========================================
      // FULL PAGE BACKGROUND
      // ========================================
      body: Stack(
        children: [
          // Same green wave and helping-hands artwork.
          Positioned.fill(
            child: Image.asset(
              'assets/images/left_panel_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // Subtle dark gradient for readable text.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xA80B3521), Color(0x390B3521)],
                ),
              ),
            ),
          ),

          // ========================================
          // SCROLLABLE ABOUT CONTENT
          // ========================================
          SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),

                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 18 : 32,
                    vertical: isMobile ? 30 : 48,
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ========================================
                      // PAGE INTRODUCTION
                      // ========================================
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ABOUT AIDTRACK',
                              style: TextStyle(
                                color: AppColors.accentYellow,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.7,
                              ),
                            ),

                            const SizedBox(height: 18),

                            Text(
                              'About the System',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 32 : 44,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'Humanitarian Aid Distribution Management '
                              'System with Machine Learning-Based '
                              'Household Vulnerability Classification',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'The system is designed to address challenges '
                              'associated with manual household registration, '
                              'vulnerability assessment, and humanitarian aid '
                              'distribution tracking. It supports LGU personnel '
                              'through an organized and centralized workflow.',
                              style: TextStyle(
                                color: Color(0xFFE4EEE7),
                                fontSize: 15,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 55),

                      // ========================================
                      // MAIN ABOUT INFORMATION SURFACE
                      // ========================================
                      Container(
                        width: double.infinity,

                        padding: EdgeInsets.all(isMobile ? 20 : 32),

                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.50),
                          ),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ========================================
                            // PROJECT OBJECTIVES
                            // ========================================
                            const Text(
                              'Project Objectives',
                              style: TextStyle(
                                color: AppColors.darkText,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 22),

                            _objective(
                              'Organize household registration '
                              'and member records.',
                            ),

                            _objective(
                              'Support household vulnerability assessment.',
                            ),

                            _objective(
                              'Classify household vulnerability using '
                              'machine learning.',
                            ),

                            _objective(
                              'Manage beneficiary records and '
                              'distribution simulations.',
                            ),

                            _objective(
                              'Provide reports for LGU monitoring '
                              'and decision support.',
                            ),

                            const SizedBox(height: 25),

                            const Divider(color: Color(0xFFE0E7E2)),

                            const SizedBox(height: 28),

                            // ========================================
                            // AUTHORIZED SYSTEM USERS
                            // ========================================
                            const Text(
                              'Authorized System Users',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkText,
                              ),
                            ),

                            const SizedBox(height: 20),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final twoColumns = constraints.maxWidth >= 650;

                                final cardWidth = twoColumns
                                    ? (constraints.maxWidth - 16) / 2
                                    : constraints.maxWidth;

                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    _roleCard(
                                      width: cardWidth,
                                      icon: Icons.admin_panel_settings_outlined,
                                      title: 'LGU Administrator',
                                      description:
                                          'Manages system user accounts, '
                                          'views household records, '
                                          'and monitors system reports '
                                          'and information.',
                                    ),
                                    _roleCard(
                                      width: cardWidth,
                                      icon: Icons.badge_outlined,
                                      title: 'LGU Staff',
                                      description:
                                          'Handles household registration, '
                                          'assessment, vulnerability '
                                          'classification, beneficiary '
                                          'management, and distribution '
                                          'simulations.',
                                    ),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 30),

                            const Divider(color: Color(0xFFE0E7E2)),

                            const SizedBox(height: 28),

                            // ========================================
                            // SYSTEM TECHNOLOGY
                            // ========================================
                            const Text(
                              'System Technology',
                              style: TextStyle(
                                color: AppColors.darkText,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'AidTrack uses Flutter for the user interface, '
                              'FastAPI for backend services, PostgreSQL for '
                              'data storage, and a Random Forest machine '
                              'learning model for household vulnerability '
                              'classification.',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.7,
                                color: AppColors.greyText,
                              ),
                            ),

                            const SizedBox(height: 25),

                            // ========================================
                            // ACADEMIC PROJECT NOTICE
                            // ========================================
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),

                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F8F3),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFD5E5DA),
                                ),
                              ),

                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: AppColors.primaryGreen,
                                    size: 24,
                                  ),

                                  SizedBox(width: 12),

                                  Expanded(
                                    child: Text(
                                      'This academic project currently uses '
                                      'synthetic training data. Machine learning '
                                      'results require validation before use '
                                      'in official humanitarian aid decisions. '
                                      'Aid distribution records are simulations.',
                                      style: TextStyle(
                                        color: AppColors.darkText,
                                        fontSize: 13,
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 28),

                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.login_outlined),
                              label: const Text('Back to Sign In'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // ========================================
                      // FOOTER
                      // ========================================
                      const Center(
                        child: Text(
                          'Local Government Unit • Authorized Personnel Only',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // PROJECT OBJECTIVE ROW
  // ========================================

  Widget _objective(String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.primaryGreen,
            size: 21,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                color: AppColors.greyText,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // AUTHORIZED USER CARD
  // ========================================

  Widget _roleCard({
    required double width,
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 165),
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E7E2)),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryGreen, size: 29),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.greyText,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
