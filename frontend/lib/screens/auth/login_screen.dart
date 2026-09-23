
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

// ========================================
// LOGIN SCREEN
// ========================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Key for validating the login form
  final _formKey = GlobalKey<FormState>();

  // Controllers for the login input fields
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Hide the password when the screen first opens
  bool _hidePassword = true;

  // Dispose controllers when leaving the screen
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ========================================
  // LOGIN VALIDATION
  // ========================================

  void _signIn() {
    // Check if the input fields are valid
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Login UI is ready. Backend connection will be added later.',
          ),
        ),
      );
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
        Expanded(
          child: _buildBrandingPanel(),
        ),

        // RIGHT SIDE: Login form and wave decoration
        Expanded(
          child: Stack(
            children: [
              // Top-right light green wave decoration
              Positioned(
                top: 0,
                right: 0,
                child: _buildTopDecoration(),
              ),

              // Center the complete login form
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 20,
                  ),

                  // Keep the login form at a readable width
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 420,
                    ),

                    // Display the login form
                    child: _buildLoginForm(),
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

          // Fill the green panel with the helping-hands image
          Positioned.fill(
            child: Image.asset(
              'assets/images/left_panel_bg.png',

              // Fill the panel without leaving empty spaces
              fit: BoxFit.cover,

              // Keep the center of the image visible
              alignment: const Alignment(0.5, -0.5),
            ),
          ),

          // ========================================
          // DARK IMAGE OVERLAY
          // ========================================

          // Add a subtle green overlay for readable text
          Positioned.fill(
            child: Container(
              color: AppColors.primaryGreen.withValues(
                alpha: 0.10,
              ),
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
                const Spacer(),
                
                // ========================================
                // MAIN SYSTEM TITLE
                // ========================================
            
                // Display the system title at the center
                Text.rich(
                    const TextSpan(
                      children: [
                        // First part of the system title
                        TextSpan(
                          text: 'Humanitarian Aid\n'
                              'Distribution\n'
                              'Management\n',
                          style: TextStyle(
                            color: AppColors.white,
                          ),
                        ),

                        // Highlight the last word in yellow
                        TextSpan(
                          text: 'System',
                          style: TextStyle(
                            color: AppColors.accentYellow,
                          ),
                        ),
                      ],
                    ),

                    // Make the system title bigger and bold
                    style: const TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.bold,
                      height: 1.2,  
                    ),

                    // Align the title text at the center
                    textAlign: TextAlign.left,
                  ),

                const Spacer(),

                // Small yellow line above the tagline
                Container(
                  width: 36,
                  height: 4,

                  decoration: BoxDecoration(
                    color: AppColors.accentYellow,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),

                const SizedBox(height: 20),

                // Bottom tagline
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
          Positioned.fill(
            child: CustomPaint(
              painter: _TopWavePainter(),
            ),
          ),

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
              child: CustomPaint(
                painter: _MobileBottomWavePainter(),
              ),
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
              child: CustomPaint(
                painter: _TopWavePainter(),
              ),
            ),
          ),

          // ========================================
          // MOBILE LOGIN FORM
          // ========================================

          // Allow the form and footer to scroll together
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                24,
                30,
                24,
                40,
              ),

              // Keep the form at a readable width
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 420,
                  ),
                  child: _buildLoginForm(isMobile: true),
                ),
              ),
            ),
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

            style: TextStyle(
              color: AppColors.greyText,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 20),

          // ========================================
          // EMAIL FIELD
          // ========================================

          TextFormField(
            controller: _emailController,

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

              if (!RegExp(
                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
              ).hasMatch(value.trim())) {
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

            // Hide or show the password
            obscureText: _hidePassword,

            decoration: InputDecoration(
              hintText: 'Enter your password',

              prefixIcon: const Icon(
                Icons.lock_outline,
              ),

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

          const SizedBox(height: 16),

          // ========================================
          // SIGN IN BUTTON
          // ========================================

          ElevatedButton(
            // Run login validation when clicked
            onPressed: _signIn,

            child: const Text(
              'Sign In',

              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ========================================
          // ADMINISTRATOR INFORMATION
          // ========================================

          const Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "Don't have an account? ",

                    style: TextStyle(
                      color: AppColors.greyText,
                    ),
                  ),

                  TextSpan(
                    text: 'Contact your administrator.',

                    style: TextStyle(
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              textAlign: TextAlign.center,
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
                style: TextStyle(
                  color: AppColors.greyText,
                  fontSize: 12,
                ),
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

                style: TextStyle(
                  color: AppColors.greyText,
                  fontSize: 12,
                ),
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
    final lightGreenPaint = Paint()
      ..color = const Color(0xFFF1F8F3);

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
      ..color = const Color(0xFFDDECE2).withValues(
        alpha: 0.65,
      );

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
    final firstWavePaint = Paint()
      ..color = const Color(0xFFF1F8F3);

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
    final secondWavePaint = Paint()
      ..color = const Color(0xFFDDEEE2);

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
    final thirdWavePaint = Paint()
      ..color = const Color(0xFFEAF5EC);

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