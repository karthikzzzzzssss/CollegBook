import 'dart:convert';

import 'package:collegebook/app.dart';
import 'package:collegebook/features/auth/auth_api.dart';
import 'package:collegebook/features/auth/register_screen.dart';
import 'package:collegebook/features/auth/session_store.dart';
import 'package:collegebook/features/home/college_guide_api.dart';
import 'package:collegebook/features/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('shows the branded splash before opening login', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore();
    final client = MockClient((request) async => _otpSent());
    addTearDown(client.close);

    await tester.pumpWidget(
      CollegeGuideApp(
        authRepository: AuthRepository(
          client: client,
          baseUrl: 'https://test.collegebook.app/api/v1/',
        ),
        sessionStore: sessionStore,
        splashDuration: const Duration(seconds: 3),
      ),
    );

    expect(find.byKey(const Key('collegeBookSplash')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('phoneField')), findsOneWidget);
  });

  testWidgets('opens Home directly when a session is saved', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore()..accessToken = 'saved-token';
    final client = MockClient((request) async => _otpSent());
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('phoneField')), findsNothing);
  });

  testWidgets('shows the native CollegeBook phone sign-in design', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore();
    final client = MockClient((request) async => _otpSent());
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.

    expect(find.byKey(const Key('collegeBookLoginArtwork')), findsOneWidget);
    expect(find.text("Let's get started"), findsOneWidget);
    expect(find.byKey(const Key('phoneField')), findsOneWidget);
    expect(find.byKey(const Key('continueButton')), findsOneWidget);
    expect(
      find.text("We'll send a 4-digit OTP to verify your number"),
      findsOneWidget,
    );
  });

  testWidgets(
    'rejects an invalid Indian mobile number without an API request',
    (WidgetTester tester) async {
      _setPhoneViewport(tester);
      var requestCount = 0;
      final sessionStore = _MemorySessionStore();
      final client = MockClient((request) async {
        requestCount++;
        return _otpSent();
      });
      addTearDown(client.close);

      await tester.pumpWidget(_app(client, sessionStore));
      await tester.pump(); // Session check.
      await tester.enterText(find.byKey(const Key('phoneField')), '93903');
      await tester.ensureVisible(find.byKey(const Key('continueButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continueButton')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid number'), findsOneWidget);
      expect(requestCount, 0);
    },
  );

  testWidgets('blocks a mobile number that does not start with 6, 7, 8 or 9', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore();
    final client = MockClient((request) async => _otpSent());
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.
    await tester.enterText(find.byKey(const Key('phoneField')), '1');
    await tester.pump();

    expect(find.text('Number must start with 6, 7, 8, or 9'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('phoneField')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('sends phone to API and displays its SMS response', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    http.Request? capturedRequest;
    final sessionStore = _MemorySessionStore();
    final client = MockClient((request) async {
      capturedRequest = request;
      return _otpSent();
    });
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.
    await tester.enterText(find.byKey(const Key('phoneField')), '9390391008');
    await tester.ensureVisible(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();

    expect(capturedRequest?.url.path, '/api/v1/auth/login/');
    expect(jsonDecode(capturedRequest!.body), {'phone_number': '9390391008'});
    expect(find.byKey(const Key('otpField')), findsOneWidget);
    expect(
      find.text('Enter the 4-digit code sent to\n+91 93903 91008'),
      findsOneWidget,
    );
    expect(find.text("Didn't receive the OTP?"), findsOneWidget);
    expect(find.text('Resend in'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text("Didn't receive the OTP?")).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('verifyButton'))).dy),
    );
    expect(
      find.text('By continuing you agree to our Terms & Privacy Policy'),
      findsOneWidget,
    );
    expect(find.text('Test OTP sent by SMS.'), findsOneWidget);
    expect(sessionStore.accessToken, isNull);
  });

  testWidgets('verifies SMS OTP, saves returned tokens, and opens Home', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore();
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body.containsKey('otp')) {
        expect(body, {'phone_number': '9390391008', 'otp': '1234'});
        return _loginSuccess();
      }
      return _otpSent();
    });
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.
    await tester.enterText(find.byKey(const Key('phoneField')), '9390391008');
    await tester.ensureVisible(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otpField')), '1234');
    await tester.ensureVisible(find.byKey(const Key('verifyButton')));
    await tester.pumpAndSettle();
    // The "OTP sent" message stands in for the Android toast; clear it.
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('verifyButton'))))
        .removeCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.byKey(const Key('verifyButton')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(const Key('mainNavigation')), findsOneWidget);
    expect(sessionStore.accessToken, 'test-access-token');
    expect(sessionStore.refreshToken, 'test-refresh-token');
  });

  testWidgets('shows server errors and remains on the phone step', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore();
    final client = MockClient(
      (request) async => _jsonResponse({
        'status': false,
        'description': 'The server rejected this number.',
      }, statusCode: 400),
    );
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.
    await tester.enterText(find.byKey(const Key('phoneField')), '9390391008');
    await tester.ensureVisible(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();

    expect(find.text('The server rejected this number.'), findsOneWidget);
    expect(find.byKey(const Key('phoneField')), findsOneWidget);
    expect(find.byKey(const Key('otpField')), findsNothing);
  });

  testWidgets('registers a verified new account and opens Home', (
    WidgetTester tester,
  ) async {
    _setPhoneViewport(tester);
    final sessionStore = _MemorySessionStore();
    http.Request? registrationRequest;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body.containsKey('otp')) {
        return _jsonResponse({'status': true, 'message': 'NEW_USER'});
      }
      if (body.containsKey('name')) {
        registrationRequest = request;
        return _jsonResponse({
          'status': true,
          'message': 'PROFILE_CREATED',
          'data': {'access': 'new-user-access-token'},
        });
      }
      return _otpSent();
    });
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.
    await tester.enterText(find.byKey(const Key('phoneField')), '9390391008');
    await tester.ensureVisible(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continueButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otpField')), '1234');
    await tester.ensureVisible(find.byKey(const Key('verifyButton')));
    await tester.pumpAndSettle();
    // The "OTP sent" message stands in for the Android toast; clear it.
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('verifyButton'))))
        .removeCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.byKey(const Key('verifyButton')));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Full name *'), findsOneWidget);
    expect(find.text('+91 9390391008'), findsNothing);

    await tester.tap(find.byKey(const Key('registrationContinueButton')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(registrationRequest, isNull);

    await tester.enterText(
      find.byKey(const Key('registrationNameField')),
      '  A Student  ',
    );
    await tester.tap(find.byKey(const Key('registrationContinueButton')));
    await tester.pumpAndSettle();

    expect(registrationRequest?.url.path, '/api/v1/auth/register/');
    expect(jsonDecode(registrationRequest!.body), {
      'phone_number': '9390391008',
      'name': 'A Student',
    });
    expect(find.byType(HomeShell), findsOneWidget);
    expect(sessionStore.accessToken, 'new-user-access-token');
    expect(sessionStore.refreshToken, isNull);
  });

  testWidgets('shows the CollegeBook home design and bottom navigation', (
    WidgetTester tester,
  ) async {
    final sessionStore = _MemorySessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          apiRepository: _apiRepository(sessionStore),
          sessionStore: sessionStore,
        ),
      ),
    );

    expect(find.byKey(const Key('homeOverviewPage')), findsOneWidget);
    expect(find.byKey(const Key('mainNavigation')), findsOneWidget);
    // First load: only the banner and the spinner, no bare section titles.
    expect(find.byKey(const Key('homeLoading')), findsOneWidget);
    expect(find.text('Catch up on the latest updates!'), findsNothing);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('homeLoading')), findsNothing);
    expect(find.text('Explore Admission Guidance'), findsOneWidget);
    expect(find.text('Catch up on the latest updates!'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mainNavigation')),
        matching: find.text('Community'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('communityScreen')), findsOneWidget);
    await tester.tap(find.text('Q&A'));
    await tester.pumpAndSettle();
    expect(find.text('No discussions yet'), findsOneWidget);
    expect(find.text('Community'), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mainNavigation')),
        matching: find.text('Cutoff'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collegeScreen')), findsOneWidget);
    expect(find.text('CutOffs & Matchings'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mainNavigation')),
        matching: find.text('Mentor'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mentorScreen')), findsOneWidget);
    expect(find.text('No PG talks available at the moment.'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mainNavigation')),
        matching: find.text('Videos'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('videosScreen')), findsOneWidget);
    expect(
      find.text("We're working on adding reels — pull down to refresh."),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mainNavigation')),
        matching: find.text('Premium'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('premiumScreen')), findsOneWidget);
    expect(find.text('Confused between plans?'), findsOneWidget);
  });

  testWidgets('fits the phone sign-in screen without overflowing', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessionStore = _MemorySessionStore();
    final client = MockClient((request) async => _otpSent());
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, sessionStore));
    await tester.pump(); // Session check.

    expect(find.byKey(const Key('continueButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(392, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

CollegeGuideApp _app(http.Client client, _MemorySessionStore sessionStore) {
  return CollegeGuideApp(
    authRepository: AuthRepository(
      client: client,
      baseUrl: 'https://test.collegebook.app/api/v1/',
    ),
    apiRepository: _apiRepository(sessionStore),
    sessionStore: sessionStore,
    splashDuration: Duration.zero,
  );
}

CollegeGuideApiRepository _apiRepository(SessionStore sessionStore) {
  final client = MockClient(
    (_) async => _jsonResponse({
      'status': true,
      'data': {'results': <Map<String, Object?>>[]},
    }),
  );
  addTearDown(client.close);
  return CollegeGuideApiRepository(
    client: client,
    sessionStore: sessionStore,
    baseUrl: 'https://test.collegebook.app/api/v1/',
  );
}

http.Response _otpSent() {
  return _jsonResponse({
    'status': true,
    'message': 'OTP_SENT',
    'description': 'Test OTP sent by SMS.',
  });
}

http.Response _loginSuccess() {
  return _jsonResponse({
    'status': true,
    'message': 'LOGIN_SUCCESS',
    'description': 'Login successful.',
    'data': {'access': 'test-access-token', 'refresh': 'test-refresh-token'},
  });
}

http.Response _jsonResponse(Map<String, Object?> body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

class _MemorySessionStore implements SessionStore {
  String? name;
  String? phone;

  @override
  Future<void> saveProfile({String? name, String? phone}) async {
    this.name = name ?? this.name;
    this.phone = phone ?? this.phone;
  }

  @override
  Future<({String? name, String? phone})> readProfile() async =>
      (name: name, phone: phone);

  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }
}
