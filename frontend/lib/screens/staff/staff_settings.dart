import 'package:flutter/material.dart';

import '../admin/admin_settings.dart';

// Staff uses the same profile and password form.
// The backend identifies the account through its login token.
class StaffSettings extends StatelessWidget {
  const StaffSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSettings();
  }
}