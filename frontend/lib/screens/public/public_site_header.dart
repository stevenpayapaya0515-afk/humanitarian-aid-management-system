import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared public navigation for Home and About.
enum PublicSitePage { home, about, login }

enum _PublicMenuChoice { home, about, coreFunctions, signIn }

Route<void> publicTabRoute(Widget page, {required bool fromRight, required bool animate}) {
  return PageRouteBuilder<void>(
    transitionDuration: Duration(milliseconds: animate ? 360 : 0),
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) => SlideTransition(
      position: animation.drive(CurveTween(curve: Curves.easeOutCubic)).drive(
        Tween<Offset>(begin: Offset(fromRight ? 1.0 : -1.0, 0), end: Offset.zero),
      ),
      child: child,
    ),
  );
}

/// Clearly visible directional slide between the public pages.
Route<void> publicSiteSlideRoute(
  Widget page, {
  required bool enterFromRight,
}) {
  final start = Offset(enterFromRight ? 1.0 : -1.0, 0);
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 680),
    reverseTransitionDuration: const Duration(milliseconds: 520),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
        reverseCurve: Curves.easeInOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(begin: start, end: Offset.zero).animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.87, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Consistent AidTrack navigation trigger used by Home, About and Login.
/// Dark-green tile, subtle yellow border, and three rounded menu strokes.
class AidTrackPublicMenuTrigger extends StatelessWidget {
  const AidTrackPublicMenuTrigger({
    super.key,
    required this.onPressed,
    this.mobile = false,
  });
  final bool mobile;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Open navigation menu',
      child: Semantics(
        label: 'Open navigation menu',
        button: true,
        child: Material(
          color: mobile ? AppColors.primaryGreen : const Color(0xFF104C37),
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0x77FFCA28)),
              ),
              child: Center(
                child: SizedBox(
                  width: 21,
                  height: 17,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _menuStroke(const Color(0xFFFFFFFF), 21),
                      _menuStroke(const Color(0xFFFFCA28), 21),
                      _menuStroke(const Color(0xFFFFFFFF), 21),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuStroke(Color color, double width) {
    return Container(
      width: width,
      height: 2.5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class PublicSiteHeader extends StatelessWidget implements PreferredSizeWidget {
  const PublicSiteHeader({
    super.key,
    required this.selectedPage,
    required this.onHome,
    required this.onAbout,
    this.onDrawerHome,
    this.onDrawerAbout,
    required this.onCoreFunctions,
    required this.onSignIn,
  });

  final PublicSitePage selectedPage;
  final VoidCallback onHome;
  final VoidCallback onAbout;
  final VoidCallback? onDrawerHome;
  final VoidCallback? onDrawerAbout;
  final VoidCallback onCoreFunctions;
  final VoidCallback onSignIn;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  /// Own dialog route makes both opening and closing a real swipe animation.
  /// Wait for the closing animation to finish before changing the page.
  Future<void> _openNavigation(BuildContext context, bool mobile) async {
    final navigator = Navigator.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = mobile ? width * 0.86 : 360.0;

    final menu = RawDialogRoute<_PublicMenuChoice>(
      barrierDismissible: true,
      barrierLabel: 'Close navigation menu',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 550),
      pageBuilder: (dialogContext, _, _) => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -250) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: PublicSiteMobileDrawer(
              selectedPage: selectedPage,
              onHome: () => Navigator.of(dialogContext).pop(_PublicMenuChoice.home),
              onAbout: () => Navigator.of(dialogContext).pop(_PublicMenuChoice.about),
              onCoreFunctions: () => Navigator.of(dialogContext).pop(_PublicMenuChoice.coreFunctions),
              onSignIn: () => Navigator.of(dialogContext).pop(_PublicMenuChoice.signIn),
            ),
          ),
        ),
      ),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1.0, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );

    final selection = await navigator.push<_PublicMenuChoice>(menu);
    // navigator.push completes at pop; this waits for the entire slide-out.
    await menu.completed;
    if (!context.mounted) return;
    switch (selection) {
      case _PublicMenuChoice.home:
        (onDrawerHome ?? onHome)();
        break;
      case _PublicMenuChoice.about:
        (onDrawerAbout ?? onAbout)();
        break;
      case _PublicMenuChoice.coreFunctions:
        onCoreFunctions();
        break;
      case _PublicMenuChoice.signIn:
        onSignIn();
        break;
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: const Color(0xFF063D29),
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 76,
      actions: const [SizedBox.shrink()],
      flexibleSpace: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, viewport) {
            final width = viewport.maxWidth;
            final compact = width < 950;
            final showDescriptor = width >= 1250;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: double.infinity),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width < 700 ? 18 : 24),
                  child: Row(
                    children: [
                      // One menu trigger on the left at every screen width.
                      AidTrackPublicMenuTrigger(
                        mobile: width < 700,
                        onPressed: () => _openNavigation(context, compact),
                      ),
                      SizedBox(width: width < 700 ? 28 : (compact ? 20 : 10)),
                      // Mobile: text only; desktop: keep the original logo.
                      _publicBrand(
                        onHome,
                        fontSize: compact ? 23 : 25,
                        showSymbol: !compact,
                      ),
                      if (showDescriptor) ...[
                        const SizedBox(width: 22),
                        Container(width: 1, height: 32, color: Colors.white30),
                        const SizedBox(width: 19),
                        const Text(
                          'HUMANITARIAN AID\nMANAGEMENT SYSTEM',
                          style: TextStyle(
                            color: Color(0xFFD8E9DE),
                            fontSize: 10,
                            letterSpacing: 1.05,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (!compact) ...[
                        _PublicNavLink(
                          label: 'Home',
                          selected: selectedPage == PublicSitePage.home,
                          onTap: onHome,
                        ),
                        const SizedBox(width: 8),
                        _PublicNavLink(
                          label: 'About',
                          selected: selectedPage == PublicSitePage.about,
                          onTap: onAbout,
                        ),
                        const SizedBox(width: 8),
                        _PublicNavLink(
                          label: 'Core Functions',
                          selected: false,
                          onTap: onCoreFunctions,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Sliding panel content is shared on desktop and mobile.
class PublicSiteMobileDrawer extends StatelessWidget {
  const PublicSiteMobileDrawer({
    super.key,
    required this.selectedPage,
    required this.onHome,
    required this.onAbout,
    required this.onCoreFunctions,
    required this.onSignIn,
  });

  final PublicSitePage selectedPage;
  final VoidCallback onHome;
  final VoidCallback onAbout;
  final VoidCallback onCoreFunctions;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryGreen,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 17),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _publicBrand(onHome, fontSize: 19, drawerTile: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close navigation',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(color: Color(0x55FFCA28), height: 1),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _drawerItem(
                      label: 'Home',
                      icon: Icons.home_outlined,
                      selected: selectedPage == PublicSitePage.home,
                      onTap: onHome,
                    ),
                    _drawerItem(
                      label: 'About',
                      icon: Icons.info_outline_rounded,
                      selected: selectedPage == PublicSitePage.about,
                      onTap: onAbout,
                    ),
                    _drawerItem(
                      label: 'Core Functions',
                      icon: Icons.grid_view_rounded,
                      selected: false,
                      onTap: onCoreFunctions,
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Color(0x44FFFFFF)),
                    const SizedBox(height: 14),
                    Material(
                      color: AppColors.accentYellow,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onSignIn,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login_rounded, color: Color(0xFF073D29), size: 20),
                              SizedBox(width: 9),
                              Flexible(
                                child: Text(
                                  'Authorized Personnel Sign In',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF073D29),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 20),
              child: Text(
                'LOCAL GOVERNMENT UNIT  •  AUTHORIZED PERSONNEL ONLY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.5,
                  color: Color(0xFFB9D8C8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0x334C9B73) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? AppColors.accentYellow : Colors.white,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? AppColors.accentYellow : Colors.white,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.chevron_right_rounded, color: AppColors.accentYellow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _publicBrand(
  VoidCallback onTap, {
  double fontSize = 25,
  double symbolSize = 53,
  bool showSymbol = true,
  bool drawerTile = false,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSymbol) ...[
          if (drawerTile)
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Image.asset('assets/images/aidtrack_symbol.png', fit: BoxFit.contain),
            )
          else
            SizedBox(
            width: symbolSize,
            height: symbolSize,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                0, 0, 0, 0, 255,
                -0.22, 0, 0, 0, 255,
                -1, 0, 0, 0, 255,
                0, 0, 0, 1, 0,
              ]),
              child: Image.asset(
                'assets/images/aidtrack_symbol.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 11),
        ],
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'Aid', style: TextStyle(color: Colors.white)),
              TextSpan(
                text: 'Track',
                style: TextStyle(color: AppColors.accentYellow),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
        ),
      ],
    ),
  );
}

/// Slightly square hover background; avoid the default pill-shaped overlay.
class _PublicNavLink extends StatefulWidget {
  const _PublicNavLink({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PublicNavLink> createState() => _PublicNavLinkState();
}

class _PublicNavLinkState extends State<_PublicNavLink> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovering) {
          if (_hovering != hovering) setState(() => _hovering = hovering);
        },
        borderRadius: BorderRadius.circular(6),
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.white12,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: 43,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovering ? const Color(0x24FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected ? AppColors.accentYellow : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                width: widget.selected ? 34 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.accentYellow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
