import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

/// Form only: the existing LoginScreen supplies the left panel and background.
/// The server, not this widget, authorizes and consumes the invitation token.
class StaffInvitationRegistrationForm extends StatefulWidget {
  final String invitationToken;
  final VoidCallback onBackToLogin;

  const StaffInvitationRegistrationForm({
    super.key,
    required this.invitationToken,
    required this.onBackToLogin,
  });

  @override
  State<StaffInvitationRegistrationForm> createState() =>
      _StaffInvitationRegistrationFormState();
}

class _StaffInvitationRegistrationFormState
    extends State<StaffInvitationRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _employeeNo = TextEditingController();
  final _contact = TextEditingController();
  final _position = TextEditingController();
  final _office = TextEditingController();
  final _barangay = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _checking = true;
  bool _submitting = false;
  bool _registered = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _consent = false;
  int _step = 0; // 0 = Employee, 1 = Security, 2 = Complete
  String? _email;
  String? _error;

  @override
  void initState() {
    super.initState();
    _validateInvitation();
  }

  @override
  void dispose() {
    for (final controller in [
      _first,
      _middle,
      _last,
      _employeeNo,
      _contact,
      _position,
      _office,
      _barangay,
      _address,
      _password,
      _confirm,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _errorFrom(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {
      // Avoid exposing backend internals for non-JSON responses.
    }
    if (response.statusCode == 410) {
      return 'Invalid, expired or already used invitation. Ask your LGU administrator for a new one.';
    }
    if (response.statusCode == 422) {
      return 'Check the employee information and password requirements.';
    }
    return 'Unable to complete the request. Please try again.';
  }

  Future<void> _validateInvitation() async {
    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/staff-invitations/validate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': widget.invitationToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _error = _errorFrom(response));
        return;
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['email'] is! String) {
        throw const FormatException('Invalid invitation response');
      }
      setState(() => _email = body['email'] as String);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Invitation check timed out.');
    } on http.ClientException {
      if (mounted) setState(() => _error = 'Cannot connect to AidTrack.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not validate this invitation.');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _register() async {
    if (_submitting || _email == null) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      setState(() => _error = 'Please read and agree to the Privacy Notice.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/staff-invitations/accept'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': widget.invitationToken,
              'first_name': _first.text.trim(),
              'middle_name': _middle.text.trim().isEmpty
                  ? null
                  : _middle.text.trim(),
              'last_name': _last.text.trim(),
              'employee_number': _employeeNo.text.trim().isEmpty
                  ? null
                  : _employeeNo.text.trim(),
              'contact_number': _contact.text.trim(),
              'position': _position.text.trim(),
              'office': _office.text.trim(),
              'assigned_barangay': _barangay.text.trim().isEmpty
                  ? null
                  : _barangay.text.trim(),
              'home_address': _address.text.trim().isEmpty
                  ? null
                  : _address.text.trim(),
              'privacy_consent': _consent,
              'password': _password.text,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      if (response.statusCode == 201) {
        _password.clear();
        _confirm.clear();
        setState(() {
          _registered = true;
          _step = 2;
        });
      } else {
        setState(() {
          _error = _errorFrom(response);
          if (response.statusCode == 410) _email = null;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'Request timed out. Ask the administrator to check whether your account was created before trying again.',
        );
      }
    } on http.ClientException {
      if (mounted) setState(() => _error = 'Cannot connect to the server.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Registration could not be confirmed.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().length < 2) {
      return 'Please enter at least 2 characters.';
    }
    return null;
  }

  Widget _input(
    String title,
    TextEditingController controller, {
    bool optional = false,
    int maxLength = 100,
    TextInputType? keyboard,
    String? hintText,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_submitting,
        maxLength: maxLength,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,

        // Revalidate when the user corrects an input.
        autovalidateMode: AutovalidateMode.onUserInteraction,

        textCapitalization: keyboard == TextInputType.phone
            ? TextCapitalization.none
            : TextCapitalization.words,

        decoration: InputDecoration(
          labelText: optional ? '$title (optional)' : '$title *',

          // Show an example inside the empty field.
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFF9AA5A0), fontSize: 13),

          counterText: '',
        ),

        validator: validator ?? (optional ? null : _required),
      ),
    );
  }

  Widget _notice(String message) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 10),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.red),
    ),
  );

  void _showPrivacyNotice() {
    const green = Color(0xFF185C37);

    Widget section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600,
            color: Color(0xFF26382D),
          )),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(
            fontSize: 14, height: 1.6, color: Color(0xFF526158),
          )),
        ],
      ),
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        scrollable: true,
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF6EF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.privacy_tip_outlined, color: green, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Staff Privacy Notice', style: TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w700,
                  color: Color(0xFF26382D),
                )),
                SizedBox(height: 4),
                Text('How AidTrack uses your information', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.normal,
                  color: Color(0xFF68766D),
                )),
              ],
            )),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1, color: Color(0xFFE6ECE8)),
              const SizedBox(height: 20),
              section('Information we collect',
                'Your name, work assignment and contact details, plus your '
                'employee number and home address if you provide them.'),
              section('Why we collect it',
                'To create and manage your LGU Staff account.'),
              section('Access and security',
                'Authorized LGU administrators can access your information '
                'for account administration. Passwords are stored as secure '
                'hashes, not in plain text.'),
              section('Your requests',
                'Contact your LGU administrator for requests about access, '
                'correction, retention or deletion of your information.'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Before production use, the LGU must publish its approved '
                  'retention period and contact details.',
                  style: TextStyle(fontSize: 12, height: 1.5,
                    color: Color(0xFF526158)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: 120,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // STEP 1 — EMPLOYEE INFORMATION
  // ========================================

  void _continueToSecurity() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _step = 1;
      _error = null;
    });

    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          alignment: 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ========================================
  // THREE-STEP PROGRESS INDICATOR
  // ========================================

  Widget _progressSteps() {
    const labels = ['Employee', 'Security', 'Complete'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 18),
                  color: i <= _step
                      ? AppColors.primaryGreen
                      : const Color(0xFFD5DED8),
                ),
              ),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: i <= _step
                      ? AppColors.primaryGreen
                      : const Color(0xFFE6EDE8),
                  child: i < _step
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i == _step
                                ? Colors.white
                                : AppColors.greyText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),

                const SizedBox(height: 5),

                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    color: i == _step
                        ? AppColors.primaryGreen
                        : AppColors.greyText,
                    fontWeight: i == _step
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ========================================
  // REGISTRATION RIGHT-PANEL CONTENT
  // ========================================

  @override
  Widget build(BuildContext context) {
    // Loading invitation validation.
    if (_checking) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Validating Staff invitation...'),
        ],
      );
    }

    // Invalid, expired, or already-used invitation.
    if (_email == null && !_registered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, color: Colors.red, size: 52),

          const SizedBox(height: 12),

          const Text(
            'Invitation Required',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),

          _notice(
            _error ?? 'Registration is available by LGU invitation only.',
          ),

          ElevatedButton(
            onPressed: widget.onBackToLogin,
            child: const Text('Back to Sign In'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AidTrack logo
        Center(
          child: Image.asset('assets/images/aidtrack_logo.png', width: 110),
        ),

        const SizedBox(height: 10),

        const Text(
          'Staff Registration',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),

        const Text(
          'For LGU Staff with an official invitation only.',
          style: TextStyle(color: AppColors.greyText),
        ),

        // Progress indicator shared by all three steps.
        _progressSteps(),

        // ========================================
        // STEP 3 — COMPLETED REGISTRATION
        // ========================================
        if (_registered) ...[
          const SizedBox(height: 12),

          const Icon(
            Icons.check_circle,
            color: AppColors.primaryGreen,
            size: 58,
          ),

          const SizedBox(height: 12),

          const Text(
            'Staff Registration Complete!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          const Text(
            'Your Staff account is ready. You can sign in now.',
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: widget.onBackToLogin,
            child: const Text('Go to Login'),
          ),
        ] else
          // ========================================
          // REGISTRATION FORM
          // ========================================
          Form(
            key: _formKey,

            child: _step == 0
                // ========================================
                // STEP 1 — EMPLOYEE INFORMATION
                // ========================================
                ? Column(
                    key: const ValueKey('employee-step'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Step 1 — Employee Information',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Email is provided by the invitation.
                      TextFormField(
                        initialValue: _email,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Invited Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),

                      const SizedBox(height: 12),

                      _input('First name', _first, maxLength: 50),

                      _input(
                        'Middle name',
                        _middle,
                        optional: true,
                        maxLength: 50,
                      ),

                      _input('Last name', _last, maxLength: 50),

                      _input(
                        'Employee number',
                        _employeeNo,
                        optional: true,
                        maxLength: 32,
                        hintText: 'e.g., LGU-2026-001',
                        validator: (value) {
                          final v = value?.trim() ?? '';

                          if (v.isEmpty) {
                            return null;
                          }

                          if (!RegExp(r'^[A-Za-z0-9-]{3,32}$').hasMatch(v)) {
                            return 'Use 3–32 letters, numbers or hyphens.';
                          }

                          return null;
                        },
                      ),

                      _input(
                        'Contact number',
                        _contact,
                        maxLength: 11,
                        keyboard: TextInputType.phone,
                        hintText: 'e.g., 09123456789',
                        validator: (value) {
                          final phone = value?.trim() ?? '';

                          if (!RegExp(r'^09\d{9}$').hasMatch(phone)) {
                            return 'Enter an 11-digit mobile number starting with 09.';
                          }

                          return null;
                        },
                      ),

                      _input('Position', _position, maxLength: 100),

                      _input(
                        'Office / Department',
                        _office,
                        maxLength: 100,
                        hintText: 'e.g., City Social Welfare Office',
                      ),

                      _input(
                        'Assigned barangay',
                        _barangay,
                        optional: true,
                        maxLength: 100,
                      ),

                      _input(
                        'Home address',
                        _address,
                        optional: true,
                        maxLength: 255,
                      ),

                      const SizedBox(height: 8),

                      ElevatedButton.icon(
                        onPressed: _continueToSecurity,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Continue to Account Security'),
                      ),

                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: widget.onBackToLogin,
                        child: const Text('Back to Sign In'),
                      ),
                    ],
                  )
                // ========================================
                // STEP 2 — ACCOUNT SECURITY
                // ========================================
                : Column(
                    key: const ValueKey('security-step'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Step 2 — Account Security',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Creating an account for $_email',
                        style: const TextStyle(color: AppColors.greyText),
                      ),

                      const SizedBox(height: 16),

                      // Create password.
                      TextFormField(
                        controller: _password,
                        enabled: !_submitting,
                        obscureText: _hidePassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Create password *',
                          helperText: '12–64 characters; uppercase, lowercase, number, symbol.',
                          helperMaxLines: 2,
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

                        validator: (value) {
                          final password = value ?? '';

                          if (password.length < 12 || password.length > 64) {
                            return 'Use 12–64 characters.';
                          }

                          if (!RegExp(r'[A-Z]').hasMatch(password) ||
                              !RegExp(r'[a-z]').hasMatch(password) ||
                              !RegExp(r'\d').hasMatch(password) ||
                              !RegExp(r'[^A-Za-z0-9\s]').hasMatch(password)) {
                            return 'Add uppercase, lowercase, number and symbol.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 12),

                      // Confirm password.
                      TextFormField(
                        controller: _confirm,
                        enabled: !_submitting,
                        obscureText: _hideConfirm,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Confirm password *',
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _hideConfirm = !_hideConfirm;
                              });
                            },
                            icon: Icon(
                              _hideConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value != _password.text) {
                            return 'Passwords do not match.';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 10),

                      TextButton(
                        onPressed: _showPrivacyNotice,
                        child: const Text(
                          'Read the AidTrack Staff Privacy Notice',
                        ),
                      ),

                      CheckboxListTile(
                        value: _consent,
                        onChanged: _submitting
                            ? null
                            : (value) {
                                setState(() {
                                  _consent = value ?? false;
                                });
                              },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I have read the Privacy Notice and consent '
                          'to processing my Staff information.',
                        ),
                      ),

                      if (_error != null) _notice(_error!),

                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: _submitting ? null : _register,
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(
                          _submitting
                              ? 'Creating Account...'
                              : 'Complete Registration',
                        ),
                      ),

                      const SizedBox(height: 8),

                      TextButton.icon(
                        onPressed: _submitting
                            ? null
                            : () {
                                setState(() {
                                  _step = 0;
                                  _error = null;
                                });
                                _scrollToTop();
                              },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back to Employee Information'),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }
}
