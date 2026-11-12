import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AidTrackApp());
}

class AidTrackApp extends StatelessWidget {
  const AidTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    final invitationToken = Uri.base.queryParameters['invite'];
    return MaterialApp(
      title: 'AidTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: LoginScreen(invitationToken: invitationToken),
    );
  }
}
