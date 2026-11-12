import '../../services/auth_service.dart';
import 'staff_invitation_registration_screen.dart';
import '../admin/admin_dashboard.dart';
import '../staff/staff_dashboard.dart';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

import 'dart:async';
import '../../widgets/recaptcha_checkbox.dart';
import 'login_otp_form.dart';

import '../public/home_page_screen.dart';
import '../public/about_page_screen.dart';

// ========================================
// LOGIN SCREEN
// ========================================

class LoginScreen extends StatefulWidget {
  final String? invitationToken;

  const LoginScreen({super.key, this.invitationToken});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showInvitationForm = false;
  bool _showInvitationNoticePanel = false;

  @override
  void initState() {
    super.initState();
    _showInvitationForm = widget.invitationToken?.isNotEmpty ?? false;
  }

  Widget _buildRightPanel({bool isMobile = false}) {
    // Invitation links display the Staff registration form.
    if (_showInvitationForm && widget.invitationToken != null) {
      return StaffInvitationRegistrationForm(
        invitationToken: widget.invitationToken!,
        onBackToLogin: () {
          if (mounted) {
            setState(() {
              _showInvitationForm = false;
              _showInvitationNoticePanel = false;
            });
          }
        },
      );
    }

    // Public registration attempts show a notice in the right panel.
    if (_showInvitationNoticePanel) {
      return _buildInvitationNoticePanel();
    }

    if (_challengeId != null) {
      return LoginOtpForm(
        challengeId: _challengeId!,
        expiresAt: _challengeExpiresAt!,
        onVerified: _openDashboard,
        onBack: () {
          AuthService.logout();
          setState(() { _challengeId = null; _loginError = null; _resetCaptcha(); });
              },
      );
    }
    // Default: normal login form.
    return _buildLoginForm(isMobile: isMobile);
  }

  void _showRegistrationNotice() {
    final hasInvitationLink =
        widget.invitationToken?.trim().isNotEmpty ?? false;

    setState(() {
      _resetCaptcha();
      if (hasInvitationLink) {
        // Reopen Staff registration using the invitation.
        _showInvitationForm = true;
        _showInvitationNoticePanel = false;
      } else {
        // Public visitors cannot access Staff registration.
        _showInvitationForm = false;
        _showInvitationNoticePanel = true;
      }
    });
  }

  Widget _buildInvitationNoticePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset('assets/images/aidtrack_logo.png', width: 135),
        ),

        const SizedBox(height: 24),

        const Center(
          child: Icon(
            Icons.mark_email_unread_outlined,
            color: AppColors.primaryGreen,
            size: 50,
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          'Invitation Required',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.darkText,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        const Text(
          'Staff registration is available by invitation only. '
          'Ask your LGU Administrator to send a registration link '
          'to your email.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.greyText, height: 1.5),
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8F3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Already invited? Open the private link from your email. '
            'Without a valid, unused invitation, registration is not allowed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.primaryGreen, height: 1.4),
          ),
        ),

        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              _showInvitationNoticePanel = false;
            });
          },
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back to Login'),
        ),
      ],
    );
  }

  // Key for validating the login form
  final _formKey = GlobalKey<FormState>();

  // Controllers for the login input fields
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Hide the password when the screen first opens
  bool _hidePassword = true;

  // Prevent repeated clicks while signing in
  bool _isLoading = false;
  String? _recaptchaToken;
  int _recaptchaGeneration = 0;
  String? _challengeId;
  DateTime? _challengeExpiresAt;

  void _resetCaptcha() {
    _recaptchaToken = null;
    _recaptchaGeneration++;
  }

  void _openDashboard(Map<String, dynamic> user) {
    if (!mounted) return;
    final Widget dashboard = user['role'] == 'Admin'
        ? const AdminDashboard() : const StaffDashboard();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => dashboard), (route) => false,
    );
  }


  // Error displayed below the password field
  String? _loginError;

  // Timer for the live login-lock countdown.
  Timer? _lockTimer;
  DateTime? _lockEndsAt;
  int _remainingLockSeconds = 0;

  // Start the countdown using the backend's remaining seconds.
  void _startLockCountdown(int seconds) {
    _lockTimer?.cancel();

    if (seconds <= 0) return;

    _lockEndsAt = DateTime.now().add(Duration(seconds: seconds));

    setState(() {
      _remainingLockSeconds = seconds;
      _loginError = null;
    });

    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Calculate from the end time to avoid timer drift.
      final milliseconds = _lockEndsAt!
          .difference(DateTime.now())
          .inMilliseconds;

      final remaining = milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;

      setState(() {
        _remainingLockSeconds = remaining;
      });

      if (remaining == 0) {
        timer.cancel();
        _lockEndsAt = null;
      }
    });
  }

  // Dispose controllers when leaving the screen
  @override
  void dispose() {
    // Stop the countdown when leaving the login screen.
    _lockTimer?.cancel();

    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ========================================
  // LOGIN VALIDATION
  // ========================================

  Future<void> _signIn() async {
    // Block both button clicks and Enter during the cooldown.
    if (_isLoading || _remainingLockSeconds > 0 || _recaptchaToken == null) return;

    // Check the form before sending a request
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loginError = null;
    });

    try {
      final challenge = await AuthService.login(
        email: _emailController.text,
        password: _passwordController.text,
        recaptchaToken: _recaptchaToken!,
      );
      if (!mounted) return;
      _passwordController.clear();
      setState(() {
        _challengeId = challenge['challenge_id'] as String;
        _challengeExpiresAt = DateTime.parse(challenge['expires_at'] as String);
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      final seconds = error.retryAfterSeconds;

      if (seconds != null && seconds > 0) {
        _startLockCountdown(seconds);
      } else {
        setState(() {
          _loginError = error.message;
        });
      }
    } catch (_) {
      AuthService.logout();

      if (!mounted) return;

      setState(() {
        _loginError = 'Unable to sign in. Please try again.';
      });
    } finally {
      if (mounted) _resetCaptcha();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ========================================
  // RESPONSIVE SCREEN LAYOUT
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,

      // Check the available screen width
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Display the desktop layout on wide screens
          if (constraints.maxWidth >= 900) {
            return _buildDesktopLayout();
          }

          // Display the mobile layout on narrow screens
          return _buildMobileLayout();
        },
      ),
    );
  }

  // ========================================
  // DESKTOP / WEB LAYOUT
  // ========================================

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // LEFT SIDE: Green branding panel
        Expanded(child: _buildBrandingPanel()),

        // RIGHT SIDE: Login form and wave decoration
        Expanded(
          child: Stack(
            children: [
              // Top-right light green wave decoration
              Positioned(top: 0, right: 0, child: _buildTopDecoration()),

              // Center the complete login form
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 20,
                  ),

                  // Keep the login form at a readable width
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),

                    // Display the login form
                    child: _buildRightPanel(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ========================================
  // PUBLIC NAVIGATION MENU
  // ========================================

  Widget _buildPublicMenu({bool isMobile = false}) {
    return PopupMenuButton<String>(
      tooltip: 'Open navigation menu',
      enabled: !_isLoading,
      offset: const Offset(0, 48),
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),

      onSelected: (page) {
        if (!mounted) return;

        final Widget destination;

        if (page == 'Home') {
          destination = const HomePageScreen();
        } else if (page == 'About') {
          destination = const AboutPageScreen();
        } else {
          return;
        }

        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => destination));
      },

      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'Home',
          child: Row(
            children: [
              Icon(
                Icons.home_outlined,
                color: AppColors.primaryGreen,
                size: 20,
              ),
              SizedBox(width: 12),
              Text('Home'),
            ],
          ),
        ),

        PopupMenuItem<String>(
          value: 'About',
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primaryGreen, size: 20),
              SizedBox(width: 12),
              Text('About'),
            ],
          ),
        ),
      ],

      // The three-line menu icon.
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: isMobile
              ? AppColors.white
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMobile ? AppColors.borderColor : Colors.white54,
          ),
        ),
        child: Icon(
          Icons.menu_rounded,
          color: isMobile ? AppColors.primaryGreen : AppColors.white,
          size: 27,
        ),
      ),
    );
  }

  // ========================================
  // LEFT BRANDING PANEL
  // ========================================

  Widget _buildBrandingPanel() {
    return Container(
      // Set the main dark green background
      color: AppColors.primaryGreen,

      // Stack the background image and text
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ========================================
          // BACKGROUND IMAGE
          // ========================================

          Positioned.fill(
            child: Image.asset(
              'assets/images/left_panel_bg.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0.5, -0.5),
            ),
          ),

          // ========================================
          // DARK IMAGE OVERLAY
          // ========================================
          Positioned.fill(
            child: Container(
              color: AppColors.primaryGreen.withValues(alpha: 0.10),
            ),
          ),

          // ========================================
          // LEFT PANEL TEXT CONTENT
          // ========================================
          Padding(
            padding: const EdgeInsets.all(60),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 1),

                // ========================================
                // MAIN SYSTEM TITLE
                // ========================================
                Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(
                        text:
                            'Humanitarian Aid\n'
                            'Distribution\n'
                            'Management\n',
                        style: TextStyle(color: AppColors.white),
                      ),

                      TextSpan(
                        text: 'System',
                        style: TextStyle(color: AppColors.accentYellow),
                      ),
                    ],
                  ),

                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),

                  textAlign: TextAlign.left,
                ),

                const Spacer(),

                // Yellow line above the tagline.
                Container(
                  width: 36,
                  height: 4,

                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'People  •  Data  •  Better Tomorrow',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // ========================================
          // HAMBURGER MENU - TOP LEFT
          // ========================================
          Positioned(top: 24, left: 24, child: _buildPublicMenu()),
        ],
      ),
    );
  }

  // ========================================
  // TOP-RIGHT WAVE DECORATION
  // ========================================

  Widget _buildTopDecoration() {
    return SizedBox(
      // Control the size of the top decoration
      width: 300,
      height: 165,

      // Stack the wave background and heading
      child: Stack(
        children: [
          // Draw the light green curved wave background
          Positioned.fill(child: CustomPaint(painter: _TopWavePainter())),

          // Display the heading on top of the wave
          Positioned(
            top: 28,
            right: 35,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,

              children: [
                // Top-right heading
                const Text(
                  'Support Today\nStronger Tomorrow',

                  textAlign: TextAlign.right,

                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 10),

                // Yellow decorative line below the heading
                Container(
                  width: 45,
                  height: 4,

                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // MOBILE LAYOUT
  // ========================================

  Widget _buildMobileLayout() {
    return SafeArea(
      child: Stack(
        children: [
          // ========================================
          // MOBILE GREEN WAVE BACKGROUND
          // ========================================

          // Keep the wave across the full width at the bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 190,
            child: IgnorePointer(
              child: CustomPaint(painter: _MobileBottomWavePainter()),
            ),
          ),

          // ========================================
          // MOBILE TOP-RIGHT CURVE
          // ========================================

          // Add a soft green decoration above the AidTrack logo
          Positioned(
            top: 0,
            right: 0,
            width: 185,
            height: 95,
            child: IgnorePointer(
              child: CustomPaint(painter: _TopWavePainter()),
            ),
          ),

          // ========================================
          // MOBILE LOGIN FORM
          // ========================================

          // Allow the form and footer to scroll together
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 85, 24, 40),

              // Keep the form at a readable width
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildRightPanel(isMobile: true),
                ),
              ),
            ),
          ),

          // ========================================
          // MOBILE PUBLIC HAMBURGER MENU
          // ========================================

          // Keep this LAST so it appears above the login form.
          Positioned(
            top: 12,
            left: 12,
            child: _buildPublicMenu(isMobile: true),
          ),
        ],
      ),
    );
  }

  // ========================================
  // LOGIN FORM
  // ========================================

  Widget _buildLoginForm({bool isMobile = false}) {
    return Form(
      key: _formKey,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [
          // ========================================
          // AIDTRACK LOGO
          // ========================================

          // Display the AidTrack logo at the top of the Login form
          Center(
            child: Image.asset(
              'assets/images/aidtrack_logo.png',

              // Make the logo slightly bigger for mobile and desktop
              width: isMobile ? 185 : 170,
            ),
          ),

          // Add spacing between the logo and Welcome Back heading
          SizedBox(height: isMobile ? 38 : 22),

          // ========================================
          // WELCOME MESSAGE
          // ========================================
          const Text(
            'Welcome Back',

            style: TextStyle(
              color: AppColors.darkText,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          const Text(
            'Sign in to access your account.',

            style: TextStyle(color: AppColors.greyText, fontSize: 14),
          ),

          const SizedBox(height: 20),

          // ========================================
          // EMAIL FIELD
          // ========================================
          TextFormField(
            controller: _emailController,
            textInputAction: TextInputAction.next,

            // Display the email keyboard on mobile
            keyboardType: TextInputType.emailAddress,

            // Email input appearance
            decoration: const InputDecoration(
              hintText: 'Email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),

            // Check if the email is valid
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email.';
              }

              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                  .hasMatch(value.trim())) {
                return 'Please enter a valid email.';
              }

              return null;
            },
          ),

          const SizedBox(height: 12),

          // ========================================
          // PASSWORD FIELD
          // ========================================
          TextFormField(
            controller: _passwordController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              _signIn();
            },

            // Hide or show the password
            obscureText: _hidePassword,

            decoration: InputDecoration(
              hintText: 'Enter your password',

              prefixIcon: const Icon(Icons.lock_outline),

              // Password visibility button
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _hidePassword = !_hidePassword;
                  });
                },

                icon: Icon(
                  _hidePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),

            // Check if the password field is empty
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password.';
              }

              return null;
            },
          ),

          const SizedBox(height: 12),
          RecaptchaCheckbox(
            key: ValueKey(_recaptchaGeneration),
            onChanged: (token) {
              if (mounted) setState(() { _recaptchaToken = token; });
            },
          ),
          // Show a live countdown below the Password field.
          if (_remainingLockSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Too many failed attempts. '
                'Try again in $_remainingLockSeconds seconds.',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (_loginError != null)
            // Show ordinary login errors when no countdown is active.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _loginError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),

          const SizedBox(height: 16),

          // ========================================
          // SIGN IN BUTTON
          // ========================================
          ElevatedButton(
            // Disable Sign In while loading or temporarily locked.
            onPressed: _isLoading || _remainingLockSeconds > 0 || _recaptchaToken == null ? null : _signIn,

            child: Text(
              _isLoading ? 'Signing in...' : 'Sign In',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 16),

          // ========================================
          // ADMINISTRATOR INFORMATION
          // ========================================
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(color: AppColors.greyText),
                ),
                TextButton(
                  onPressed: _showRegistrationNotice,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    overlayColor: Colors.transparent,
                  ),
                  child: const Text(
                    'Register here',
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ========================================
          // MOBILE LGU FOOTER
          // ========================================

          // Keep the mobile footer below the administrator text
          // so they do not overlap on different phone sizes
          if (isMobile) ...[
            const SizedBox(height: 95),

            // Government building icon and LGU name
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: AppColors.primaryGreen,
                    size: 18,
                  ),

                  SizedBox(width: 8),

                  Text(
                    'Local Government Unit',
                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            // Authorized LGU personnel message
            const Center(
              child: Text(
                'For authorized LGU personnel only.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
            ),
          ],

          // ========================================
          // DESKTOP / WEB LGU FOOTER
          // ========================================

          // Display the LGU footer only on desktop
          // The mobile footer is already in _buildLoginForm()
          if (!isMobile) ...[
            // Add spacing before the desktop footer
            const SizedBox(height: 24),

            // Divider above the LGU information
            const Divider(),

            const SizedBox(height: 10),

            // Government building icon and LGU name
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,

                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: AppColors.primaryGreen,
                    size: 18,
                  ),

                  SizedBox(width: 8),

                  Text(
                    'Local Government Unit',

                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            // Authorized LGU personnel message
            const Center(
              child: Text(
                'For authorized LGU personnel only.',

                style: TextStyle(color: AppColors.greyText, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ========================================
// CUSTOM TOP-RIGHT WAVE DESIGN
// ========================================

// Draw the green waves behind the desktop heading
class _TopWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ========================================
    // FIRST WAVE: LIGHT GREEN
    // ========================================

    // Set the main wave color
    final lightGreenPaint = Paint()..color = const Color(0xFFF1F8F3);

    // Create the main curved wave
    final mainWave = Path()
      ..moveTo(size.width * 0.25, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..cubicTo(
        size.width * 0.65,
        size.height * 0.90,
        size.width * 0.35,
        size.height * 0.55,
        size.width * 0.25,
        0,
      )
      ..close();

    // Draw the main wave
    canvas.drawPath(mainWave, lightGreenPaint);

    // ========================================
    // SECOND WAVE: SOFT GREEN
    // ========================================

    // Set the second wave color
    final secondWavePaint = Paint()
      ..color = const Color(0xFFDDECE2).withValues(alpha: 0.65);

    // Create the second curved wave
    final secondWave = Path()
      ..moveTo(size.width * 0.65, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.80)
      ..cubicTo(
        size.width * 0.90,
        size.height * 0.70,
        size.width * 0.70,
        size.height * 0.35,
        size.width * 0.65,
        0,
      )
      ..close();

    // Draw the second wave
    canvas.drawPath(secondWave, secondWavePaint);
  }

  // No need to repaint unless the design changes
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

// ========================================
// CUSTOM MOBILE BOTTOM WAVE DESIGN
// ========================================

// Draw the overlapping green waves behind the mobile LGU footer
class _MobileBottomWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ========================================
    // FIRST WAVE: LIGHT GREEN BACKGROUND
    // ========================================

    // Set the first wave color
    final firstWavePaint = Paint()..color = const Color(0xFFF1F8F3);

    // Create the first smooth wave
    final firstWave = Path()
      ..moveTo(0, size.height * 0.30)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.10,
        size.width * 0.65,
        size.height * 0.70,
        size.width,
        size.height * 0.25,
      )
      // Fill the area below the wave
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Draw the first wave
    canvas.drawPath(firstWave, firstWavePaint);

    // ========================================
    // SECOND WAVE: SOFT GREEN
    // ========================================

    // Set the second wave color
    final secondWavePaint = Paint()..color = const Color(0xFFDDEEE2);

    // Create the second smooth wave
    final secondWave = Path()
      ..moveTo(0, size.height * 0.55)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.30,
        size.width * 0.60,
        size.height * 0.95,
        size.width,
        size.height * 0.50,
      )
      // Fill the area below the wave
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Draw the second wave
    canvas.drawPath(secondWave, secondWavePaint);

    // ========================================
    // THIRD WAVE: VERY LIGHT GREEN
    // ========================================

    // Set the third wave color
    final thirdWavePaint = Paint()..color = const Color(0xFFEAF5EC);

    // Create the third wave at the bottom
    final thirdWave = Path()
      ..moveTo(0, size.height * 0.80)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.55,
        size.width * 0.70,
        size.height * 1.05,
        size.width,
        size.height * 0.75,
      )
      // Fill the bottom area
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Draw the third wave
    canvas.drawPath(thirdWave, thirdWavePaint);
  }

  // The waves are static and do not need continuous repainting
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
