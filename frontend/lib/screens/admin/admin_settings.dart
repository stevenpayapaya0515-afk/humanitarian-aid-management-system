import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';

// ========================================
// ADMIN SETTINGS
// ========================================

class AdminSettings extends StatefulWidget {
  const AdminSettings({super.key});

  @override
  State<AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings> {
  final _formKey = GlobalKey<FormState>();

  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  Map<String, dynamic>? _profile;

  bool _loadingProfile = true;
  bool _saving = false;

  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _hideConfirm = true;

  String? _profileError;
  String? _passwordError;

  // Live countdown for incorrect current-password attempts.
  Timer? _lockTimer;
  DateTime? _lockEndsAt;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // ========================================
  // REQUEST HELPERS
  // ========================================

  Map<String, String> _headers() {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw const AuthException('Please log out and log in again.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  String _errorMessage(Object error, {bool changingPassword = false}) {
    if (error is AuthException) return error.message;

    // The request may have reached the server before a connection failed.
    if (changingPassword) {
      return 'Unable to confirm the password change. '
          'Log out and try signing in with your new password.';
    }

    if (error is TimeoutException) {
      return 'Loading timed out. Please click Refresh.';
    }

    if (error is http.ClientException) {
      return 'Cannot connect to the server. Check your backend.';
    }

    return 'Unable to read account details. Please try again.';
  }

  // ========================================
  // LOAD CURRENT ACCOUNT
  // ========================================

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });

    try {
      final response = await http
          .get(Uri.parse('${AuthService.baseUrl}/auth/me'), headers: _headers())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw const AuthException(
          'Your session has expired. Please log out and log in again.',
        );
      }

      if (response.statusCode != 200) {
        throw const AuthException('Unable to load your profile.');
      }

      final data = jsonDecode(response.body);

      if (data is! Map<String, dynamic> ||
          data['full_name'] is! String ||
          data['email'] is! String ||
          data['role'] is! String) {
        throw const FormatException('Invalid profile response.');
      }

      if (!mounted) return;

      setState(() {
        _profile = data;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _profileError = _errorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
        });
      }
    }
  }

  Future<void> _refreshProfileWithFeedback() async {
    if (_loadingProfile || _saving) return;

    await _loadProfile();

    if (!mounted || _profileError == null) return;

    await _showSettingsErrorDialog(
      title: 'Profile Refresh Failed',
      message: _profileError!,
    );
  }

  // ========================================
  // LIVE LOCK COUNTDOWN
  // ========================================

  void _startCountdown(int seconds) {
    _lockTimer?.cancel();

    _lockEndsAt = DateTime.now().add(Duration(seconds: seconds));

    setState(() {
      _remainingSeconds = seconds;
      _passwordError = null;
    });

    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final milliseconds = _lockEndsAt!
          .difference(DateTime.now())
          .inMilliseconds;

      final remaining = milliseconds > 0 ? (milliseconds / 1000).ceil() : 0;

      setState(() {
        _remainingSeconds = remaining;
      });

      if (remaining == 0) {
        timer.cancel();
        _lockEndsAt = null;
      }
    });
  }

  // ========================================
  // SETTINGS ERROR MODAL
  // ========================================

  Future<void> _showSettingsErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 58),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.greyText),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: AppColors.white,
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ========================================
  // CHANGE PASSWORD LOADING MODAL
  // ========================================

  void _showPasswordLoadingDialog() {
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primaryGreen,
                  strokeWidth: 3,
                ),
                SizedBox(height: 20),
                Text(
                  'Changing Password...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Please wait while your password '
                  'is securely updated.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.greyText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // CHANGE PASSWORD
  // ========================================

  // ========================================
  // CHANGE PASSWORD
  // ========================================

  Future<void> _changePassword() async {
    // Prevent repeated requests and enforce the lockout.
    if (_saving || _remainingSeconds > 0) return;

    // Validate before contacting FastAPI.
    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showSettingsErrorDialog(
        title: 'Invalid Password Information',
        message:
            'Please complete the required fields '
            'and correct the highlighted errors.',
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _passwordError = null;
    });

    // Display loading while the request is processing.
    _showPasswordLoadingDialog();

    bool passwordChanged = false;
    String? failureMessage;
    int? lockSeconds;

    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/auth/change-password'),
            headers: _headers(),

            // Preserve the exact password characters.
            body: jsonEncode({
              'current_password': _currentPassword.text,
              'new_password': _newPassword.text,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      // ======================================
      // ACCOUNT LOCKOUT
      // ======================================

      if (response.statusCode == 429) {
        lockSeconds = int.tryParse(response.headers['retry-after'] ?? '');

        if (lockSeconds != null && lockSeconds > 0) {
          failureMessage =
              'Too many failed password attempts. '
              'Please try again after $lockSeconds seconds.';
        } else {
          failureMessage =
              'Too many failed password attempts. '
              'Please wait before trying again.';
        }
      }
      // ======================================
      // SESSION EXPIRED
      // ======================================
      else if (response.statusCode == 401) {
        throw const AuthException(
          'Your session has expired. '
          'Please log out and log in again.',
        );
      }
      // ======================================
      // INCORRECT PASSWORD / VALIDATION
      // ======================================
      else if (response.statusCode == 400) {
        final data = jsonDecode(response.body);

        throw AuthException(
          data is Map<String, dynamic> && data['detail'] is String
              ? data['detail'] as String
              : 'Please check your passwords.',
        );
      } else if (response.statusCode == 422) {
        throw const AuthException(
          'Check your password entries. '
          'The new password must contain '
          '12 to 64 characters.',
        );
      }
      // ======================================
      // UNEXPECTED SERVER RESPONSE
      // ======================================
      else if (response.statusCode != 200) {
        throw const AuthException(
          'Unable to confirm the password change. '
          'Log out and try signing in with your new password.',
        );
      }
      // ======================================
      // SUCCESSFUL API RESPONSE
      // ======================================
      else {
        passwordChanged = true;
      }
    } catch (error) {
      failureMessage = _errorMessage(error, changingPassword: true);
    } finally {
      if (mounted) {
        // Close the loading modal first.
        Navigator.of(context, rootNavigator: true).pop();

        setState(() {
          _saving = false;
          _passwordError = passwordChanged ? null : failureMessage;
        });
      }
    }

    if (!mounted) return;

    // ========================================
    // START LOCKOUT COUNTDOWN IF REQUIRED
    // ========================================

    if (lockSeconds != null && lockSeconds > 0) {
      _startCountdown(lockSeconds);
    }

    // ========================================
    // ERROR MODAL
    // ========================================

    if (!passwordChanged) {
      await _showSettingsErrorDialog(
        title: 'Password Change Failed',
        message:
            failureMessage ??
            'An unexpected error occurred. '
                'Please try again.',
      );
      return;
    }

    // ========================================
    // SUCCESS: CLEAR SENSITIVE INFORMATION
    // ========================================

    _currentPassword.clear();
    _newPassword.clear();
    _confirmPassword.clear();

    // Keep the original security behavior:
    // require a new login after password change.
    AuthService.logout();

    // ========================================
    // ORIGINAL SUCCESS MODAL
    // ========================================

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: AppColors.primaryGreen,
              size: 56,
            ),
            SizedBox(height: 12),
            Text('Password Changed', textAlign: TextAlign.center),
          ],
        ),
        content: const Text(
          'Please log in using your new password.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Prevent returning to the authenticated dashboard.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ========================================
  // REUSABLE UI
  // ========================================

  Widget _panel(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E7E2)),
      ),
      child: child,
    );
  }

  Widget _profileDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.greyText, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool hidden,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
    bool submitOnEnter = false,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_saving && _remainingSeconds == 0,
      obscureText: hidden,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: submitOnEnter
          ? TextInputAction.done
          : TextInputAction.next,
      onFieldSubmitted: submitOnEnter ? (_) => _changePassword() : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: controller == _newPassword
            ? '• 12 to 64 characters\n'
                  '• At least 1 uppercase letter (A–Z)\n'
                  '• At least 1 lowercase letter (a–z)\n'
                  '• At least 1 number (0–9)\n'
                  '• At least 1 symbol (! @ #)\n'
                  '• Avoid common passwords, your name, and email'
            : null,
        helperMaxLines: 8,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: onToggle,
          tooltip: hidden ? 'Show password' : 'Hide password',
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: validator,
    );
  }

  // ========================================
  // MAIN SETTINGS SCREEN
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Account details come from the authenticated /auth/me endpoint.
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My Profile',
                      style: TextStyle(
                        color: AppColors.primaryGreen,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh profile',
                    onPressed: _loadingProfile || _saving
                        ? null
                        : _refreshProfileWithFeedback,
                    icon: const Icon(
                      Icons.refresh,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadingProfile)
                const Center(child: CircularProgressIndicator())
              else if (_profileError != null)
                Text(_profileError!, style: const TextStyle(color: Colors.red))
              else if (_profile != null) ...[
                _profileDetail('Full Name', _profile!['full_name'] as String),
                _profileDetail('Email', _profile!['email'] as String),
                _profileDetail('Role', _profile!['role'] as String),
              ] else
                const Text(
                  'No profile information available. Please click Refresh.',
                  style: TextStyle(color: AppColors.greyText),
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        _panel(
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Change Password',
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your current password and choose a new password '
                  'with at least 12 characters.',
                  style: TextStyle(color: AppColors.greyText),
                ),
                const SizedBox(height: 20),

                _passwordField(
                  controller: _currentPassword,
                  label: 'Current Password',
                  hidden: _hideCurrent,
                  onToggle: () {
                    setState(() => _hideCurrent = !_hideCurrent);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Enter your current password.';
                    }
                    if (value.length > 1024) {
                      return 'Password is too long.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                _passwordField(
                  controller: _newPassword,
                  label: 'New Password',
                  hidden: _hideNew,
                  onToggle: () {
                    setState(() => _hideNew = !_hideNew);
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter your new password.';
                    }
                    if (value.runes.length < 12 || value.runes.length > 64) {
                      return 'Use 12 to 64 characters.';
                    }
                    if (value == _currentPassword.text) {
                      return 'Choose a different password.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                _passwordField(
                  controller: _confirmPassword,
                  label: 'Confirm New Password',
                  hidden: _hideConfirm,
                  submitOnEnter: true,
                  onToggle: () {
                    setState(() => _hideConfirm = !_hideConfirm);
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Confirm your new password.';
                    }
                    if (value != _newPassword.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),

                // Display errors and the running countdown below the fields.
                if (_remainingSeconds > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Too many failed attempts. Try again in '
                      '$_remainingSeconds seconds.',
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                else if (_passwordError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _passwordError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                const SizedBox(height: 20),

                ElevatedButton.icon(
                  onPressed: _saving || _remainingSeconds > 0
                      ? null
                      : _changePassword,
                  icon: const Icon(Icons.password_outlined),
                  label: Text(_saving ? 'Saving...' : 'Change Password'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
