import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'about_page_screen.dart';
import 'public_site_header.dart';

// ========================================
// AIDTRACK PUBLIC HOME PAGE
// ========================================

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key, this.scrollToFunctions = false});

  final bool scrollToFunctions;

  @override
  State<HomePageScreen> createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _functionsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToFunctions) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCoreFunctions();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToCoreFunctions() {
    final context = _functionsKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 430),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 700;
    final headingSize = isMobile ? 32.0 : (width * 0.052).clamp(44.0, 72.0).toDouble();

    void openAbout(bool animate) {
      Navigator.of(context).pushReplacement(publicTabRoute(
        const AboutPageScreen(),
        fromRight: true,
        animate: animate,
      ));
    }

    return Scaffold(
      backgroundColor: AppColors.primaryGreen,

      appBar: PublicSiteHeader(
        selectedPage: PublicSitePage.home,
        onHome: _scrollToTop,
        onAbout: () => openAbout(true),
        onDrawerAbout: () => openAbout(false),
        onCoreFunctions: _scrollToCoreFunctions,
        onSignIn: () => Navigator.of(context).popUntil((route) => route.isFirst),
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
            controller: _scrollController,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: double.infinity),

                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 40 : 46,
                    vertical: isMobile ? 22 : 48,
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ========================================
                      // WELCOME INTRODUCTION
                      // ========================================
                      ConstrainedBox(
                        // Keep Core System Functions below the first viewport.
                        // It remains accessible by scrolling or its nav link.
                        constraints: BoxConstraints(
                          maxWidth: double.infinity,
                          minHeight: (MediaQuery.sizeOf(context).height -
                                  76 -
                                  (isMobile ? 22 : 48))
                              .clamp(0.0, double.infinity),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
                                const SizedBox(width: 22),
                                if (isMobile)
                                  Container(
                                    width: 3,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppColors.accentYellow,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  )
                                else
                                  const SizedBox(
                                    width: 48,
                                    child: Divider(
                                      color: AppColors.accentYellow,
                                      thickness: 2,
                                    ),
                                  ),
                              ],
                            ),

                            SizedBox(height: isMobile ? 14 : 18),

                            Text(
                              isMobile
                                  ? 'Humanitarian Aid Distribution Management System'
                                  : 'Humanitarian Aid Distribution\nManagement System',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: headingSize,
                                height: 1.17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            SizedBox(height: isMobile ? 14 : 18),

                            Text(
                              'With Machine Learning-Based Household '
                              'Vulnerability Classification',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 18 : 24,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),

                            SizedBox(height: isMobile ? 14 : 18),

                            Text(
                              'AidTrack is designed to support '
                              'Local Government Units in organizing '
                              'household information, conducting '
                              'vulnerability assessments, classifying '
                              'household vulnerability, and monitoring '
                              'humanitarian aid activities.',
                              style: TextStyle(
                                color: Color(0xFFE4EEE7),
                                fontSize: isMobile ? 17 : 22,
                                height: 1.5,
                              ),
                            ),

                            SizedBox(height: isMobile ? 18 : 26),

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

                      const SizedBox(height: 36),

                      // ========================================
                      // MAIN WHITE CONTENT SURFACE
                      // ========================================
                      Container(
                        key: _functionsKey,
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 5,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF19A34A),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 17),
                                const Expanded(
                                  child: Text(
                                    'Core System Functions',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 7),

                            const Padding(
                              padding: EdgeInsets.only(left: 22),
                              child: Text(
                                'AidTrack supports the following '
                                'authorized LGU workflows.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.greyText,
                                ),
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
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FCFA),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFD7E5DD)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFE2F1E7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryGreen, size: 29),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.greyText,
                    fontSize: 12.5,
                    height: 1.5,
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
