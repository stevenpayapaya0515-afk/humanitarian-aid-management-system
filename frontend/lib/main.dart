import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

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

      // Apply the existing AidTrack theme
      theme: AppTheme.lightTheme,

      // Open the login page first
      home: const LoginScreen(),
    );
  }
}