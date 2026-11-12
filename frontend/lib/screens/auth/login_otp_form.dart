import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';

/// Fits inside the existing login right panel on desktop and mobile.
class LoginOtpForm extends StatefulWidget {
  final String challengeId;
  final DateTime expiresAt;
  final ValueChanged<Map<String, dynamic>> onVerified;
  final VoidCallback onBack;
  const LoginOtpForm({super.key, required this.challengeId,
    required this.expiresAt, required this.onVerified, required this.onBack});
  @override
  State<LoginOtpForm> createState() => _LoginOtpFormState();
}

class _LoginOtpFormState extends State<LoginOtpForm> {
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  Timer? _timer;
  bool _busy = false;
  String? _error;
  int get _seconds {
    final seconds = widget.expiresAt.difference(DateTime.now()).inSeconds;
    return seconds > 0 ? seconds : 0;
  }
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {});
      if (_seconds == 0) timer.cancel();
    });
  }
  @override
  void dispose() { _timer?.cancel(); _code.dispose(); super.dispose(); }

  Future<void> _verify() async {
    if (_busy || _seconds == 0 || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final user = await AuthService.verifyOtp(widget.challengeId, _code.text);
      if (!mounted) { AuthService.logout(); return; }
      widget.onVerified(user);
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); });
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _seconds;
    return Form(key: _form, child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 46, color: Color(0xFF185C37)),
        const SizedBox(height: 16),
        const Text('Verify your email', textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Enter the six-digit code sent to your account email. Check Spam if it is missing.',
          textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextFormField(controller: _code, autofocus: true,
          keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Email verification code',
            prefixIcon: Icon(Icons.verified_user_outlined)),
          validator: (value) => value == null || value.length != 6
              ? 'Enter the six-digit code.' : null,
          onFieldSubmitted: (_) => _verify()),
        Text(seconds == 0 ? 'Code expired. Return to sign in for a new code.'
            : 'Code expires in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
          textAlign: TextAlign.center),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _busy || seconds == 0 ? null : _verify,
          child: Text(_busy ? 'Verifying...' : 'Verify and Sign In')),
        TextButton(onPressed: _busy ? null : widget.onBack,
          child: const Text('Back to sign in / request a new code')),
        const Text('For another code, sign in again. Email requests have a 60-second cooldown.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    ));
  }
}
