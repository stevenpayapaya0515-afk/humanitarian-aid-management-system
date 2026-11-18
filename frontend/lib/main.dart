import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/staff/staff_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AidTrackApp());
}

class AidTrackApp extends StatefulWidget {
  const AidTrackApp({super.key});

  @override
  State<AidTrackApp> createState() => _AidTrackAppState();
}

class _AidTrackAppState extends State<AidTrackApp> {
  late Future<String?> _sessionCheck;

  @override
  void initState() {
    super.initState();
    _sessionCheck = AuthService.restoreSession();
  }

  void _retry() {
    setState(() {
      _sessionCheck = AuthService.restoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final invitationToken = Uri.base.queryParameters['invite'];
    return MaterialApp(
      title: 'AidTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // Invitation registration always takes precedence over session restore.
      home: invitationToken != null && invitationToken.isNotEmpty
          ? LoginScreen(invitationToken: invitationToken)
          : FutureBuilder<String?>(
              future: _sessionCheck,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  // Do not discard a valid saved login on a temporary outage.
                  return Scaffold(
                    body: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_outlined, size: 40),
                              const SizedBox(height: 12),
                              const Text(
                                'Cannot verify your current session. Check FastAPI and try again.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _retry,
                                child: const Text('Retry connection'),
                              ),
                              TextButton(
                                onPressed: () {
                                  AuthService.logout();
                                  _retry();
                                },
                                child: const Text('Sign in again'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                switch (snapshot.data) {
                  case 'Admin':
                    return const AdminDashboard();
                  case 'Staff':
                    return const StaffDashboard();
                  default:
                    return const LoginScreen();
                }
              },
            ),
    );
  }
}
