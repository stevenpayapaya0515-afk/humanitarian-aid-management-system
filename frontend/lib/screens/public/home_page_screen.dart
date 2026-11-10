import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ========================================
// AIDTRACK PUBLIC HOME PAGE
// ========================================

class HomePageScreen extends StatelessWidget {
  const HomePageScreen({super.key});

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
          // Original green wave and helping-hands image.
          Positioned.fill(
            child: Image.asset(
              'assets/images/left_panel_bg.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // A single gradient makes white text readable
          // while keeping the original image visible.
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
          // SCROLLABLE PAGE CONTENT
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
                      // WELCOME INTRODUCTION
                      // ========================================
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WELCOME TO AIDTRACK',
                              style: TextStyle(
                                color: AppColors.accentYellow,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.7,
                              ),
                            ),

                            const SizedBox(height: 18),

                            Text(
                              'Humanitarian Aid Distribution '
                              'Management System',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 32 : 45,
                                height: 1.17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'With Machine Learning-Based Household '
                              'Vulnerability Classification',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'AidTrack is designed to support '
                              'Local Government Units in organizing '
                              'household information, conducting '
                              'vulnerability assessments, classifying '
                              'household vulnerability, and monitoring '
                              'humanitarian aid activities.',
                              style: TextStyle(
                                color: Color(0xFFE4EEE7),
                                fontSize: 15,
                                height: 1.7,
                              ),
                            ),

                            const SizedBox(height: 26),

                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.login_outlined, size: 19),
                              label: const Text('Authorized Personnel Sign In'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentYellow,
                                foregroundColor: AppColors.primaryGreen,
                                minimumSize: const Size(0, 50),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 55),

                      // ========================================
                      // MAIN WHITE CONTENT SURFACE
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
                            const Text(
                              'Core System Functions',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkText,
                              ),
                            ),

                            const SizedBox(height: 8),

                            const Text(
                              'AidTrack supports the following '
                              'authorized LGU workflows.',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.greyText,
                              ),
                            ),

                            const SizedBox(height: 25),

                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;

                                final columns = width >= 850
                                    ? 3
                                    : width >= 520
                                    ? 2
                                    : 1;

                                final cardWidth =
                                    (width - (columns - 1) * 16) / columns;

                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    _featureCard(
                                      width: cardWidth,
                                      icon: Icons.home_outlined,
                                      title: 'Household Registration',
                                      description:
                                          'Organize household profiles, '
                                          'addresses, and household members.',
                                    ),
                                    _featureCard(
                                      width: cardWidth,
                                      icon: Icons.assignment_outlined,
                                      title: 'Household Assessment',
                                      description:
                                          'Collect household information '
                                          'used for vulnerability assessments.',
                                    ),
                                    _featureCard(
                                      width: cardWidth,
                                      icon: Icons.analytics_outlined,
                                      title: 'Vulnerability Classification',
                                      description:
                                          'Use machine learning to classify '
                                          'households as Low, Medium, or High.',
                                    ),
                                    _featureCard(
                                      width: cardWidth,
                                      icon: Icons.people_outline,
                                      title: 'Beneficiary Management',
                                      description:
                                          'Organize beneficiary records '
                                          'and preliminary review information.',
                                    ),
                                    _featureCard(
                                      width: cardWidth,
                                      icon: Icons.inventory_2_outlined,
                                      title: 'Aid Distribution',
                                      description:
                                          'Record aid distribution simulations '
                                          'and review distribution history.',
                                    ),
                                    _featureCard(
                                      width: cardWidth,
                                      icon: Icons.bar_chart_outlined,
                                      title: 'Reports and Analytics',
                                      description:
                                          'View household statistics, '
                                          'vulnerability summaries, '
                                          'and distribution reports.',
                                    ),
                                  ],
                                );
                              },
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
  // FEATURE CARD
  // ========================================

  Widget _featureCard({
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

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryGreen, size: 27),

          const SizedBox(height: 14),

          Text(
            title,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            description,
            style: const TextStyle(
              color: AppColors.greyText,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
