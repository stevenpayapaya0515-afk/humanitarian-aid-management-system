import 'package:flutter/material.dart';

class RecaptchaCheckbox extends StatelessWidget {
  final ValueChanged<String?> onChanged;
  const RecaptchaCheckbox({super.key, required this.onChanged});
  @override
  Widget build(BuildContext context) => const Text(
    'Open AidTrack in a web browser to complete security verification.',
    textAlign: TextAlign.center,
  );
}
