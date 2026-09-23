
import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

// Import our new dashboard screen
import 'screens/dashboard/dashboard_screen.dart';

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
      // DASHBOARD UI PREVIEW
      // ========================================

      // Temporarily display the LGU Administrator Dashboard
      home: const DashboardScreen(
        role: UserRole.administrator,
      ),

      // ========================================
      // ORIGINAL LOGIN PAGE
      // ========================================

      // Restore this after testing the dashboard:
      // home: const LoginScreen(),
    );
  }
}