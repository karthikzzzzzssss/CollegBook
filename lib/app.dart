import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/auth/auth_api.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/session_store.dart';
import 'features/home/college_guide_api.dart';
import 'features/home/home_shell.dart';
import 'features/mentor/incoming_consultation.dart';
import 'features/splash/splash_screen.dart';
import 'theme/app_theme.dart';

class CollegeGuideApp extends StatelessWidget {
  const CollegeGuideApp({
    super.key,
    this.authRepository,
    this.apiRepository,
    this.sessionStore,
    this.splashDuration = const Duration(seconds: 3),
  });

  final AuthRepository? authRepository;
  final CollegeGuideApiRepository? apiRepository;
  final SessionStore? sessionStore;
  final Duration splashDuration;

  @override
  Widget build(BuildContext context) {
    final sessionGate = _SessionGate(
      authRepository: authRepository,
      apiRepository: apiRepository,
      sessionStore: sessionStore ?? SecureSessionStore(),
    );

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'CollegeGuide',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: splashDuration == Duration.zero
          ? sessionGate
          : SplashScreen(duration: splashDuration, nextScreen: sessionGate),
    );
  }
}

/// Like the native LoginActivity, which forwards straight to the home screen
/// when a session is already saved: a stored access token opens Home,
/// otherwise the login screen.
class _SessionGate extends StatefulWidget {
  const _SessionGate({
    required this.sessionStore,
    this.authRepository,
    this.apiRepository,
  });

  final SessionStore sessionStore;
  final AuthRepository? authRepository;
  final CollegeGuideApiRepository? apiRepository;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<bool> _hasSession = _readSession();

  Future<bool> _readSession() async {
    try {
      final token = await widget.sessionStore.readAccessToken();
      final store = widget.sessionStore;
      if (store is SecureSessionStore) await store.mirrorToNative();
      return token != null && token.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasSession,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(color: AppColors.primary);
        }
        if (snapshot.data!) {
          return HomeShell(
            apiRepository: widget.apiRepository,
            sessionStore: widget.sessionStore,
          );
        }
        return LoginScreen(
          authRepository: widget.authRepository,
          apiRepository: widget.apiRepository,
          sessionStore: widget.sessionStore,
        );
      },
    );
  }
}
