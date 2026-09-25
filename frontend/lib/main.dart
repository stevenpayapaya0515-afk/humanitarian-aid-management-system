import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/staff/staff_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';

void main() {
  runApp(const AidTrackApp());
}

class AidTrackApp extends StatelessWidget {
  const AidTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AidTrack',
      debugShowCheckedModeBanner: false,

      // Apply our existing green, yellow, and white theme
      theme: AppTheme.lightTheme,

      // ========================================
      // ADMIN DASHBOARD UI PREVIEW
      // ========================================

      // Temporarily display the LGU Administrator Dashboard
      home: const StaffDashboard(),

      // ========================================
      // ORIGINAL LOGIN PAGE
      // ========================================

      // Restore this after testing the dashboard:
      // home: const LoginScreen(),
    );
  }
}