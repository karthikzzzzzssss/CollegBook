import 'package:collegebook/features/home/home_shell.dart';
import 'package:collegebook/features/home/college_guide_api.dart';
import 'package:collegebook/features/auth/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('renders records from the CollegeBook API response', (
    WidgetTester tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        '{"status":true,"data":{"results":[{"id":1,"name":"API college"}]}}',
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);
    final sessionStore = _TestSessionStore();
    final repository = CollegeGuideApiRepository(
      client: client,
      sessionStore: sessionStore,
      baseUrl: 'https://test.collegebook.app/api/v1/',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApiCollectionSection(
            requestKey: 'api-render',
            repository: repository,
            load: repository.recommendedColleges,
            titleFields: const ['name'],
            subtitleFields: const [],
            icon: Icons.account_balance_outlined,
            emptyMessage: 'No colleges',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('API college'), findsOneWidget);
    expect(find.text('No colleges'), findsNothing);
  });

  testWidgets('main navigation matches the native destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_homeApp());
    await tester.pumpAndSettle();

    for (final label in const [
      'Home',
      'Cutoff',
      'Mentor',
      'Videos',
      'Community',
      'Premium',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Mentor').last);
    await tester.pumpAndSettle();
    expect(find.text('Talk Directly with PGs & Faculty'), findsOneWidget);
    expect(find.text('No PG talks available at the moment.'), findsOneWidget);

    await tester.tap(find.text('Videos').last);
    await tester.pumpAndSettle();
    expect(
      find.text('We\'re working on adding reels — pull down to refresh.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Community').last);
    await tester.pumpAndSettle();
    expect(find.text('Chats'), findsOneWidget);
    await tester.tap(find.text('Q&A').last);
    await tester.pumpAndSettle();
    expect(find.text('No discussions yet'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
  });

  // CutOffs & Matchings and Allotments are server-rendered WebViews, which
  // need a device; the Colleges list and the header are checked here.
  testWidgets('cutoff tab shows the native header and colleges empty state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_homeApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cutoff').last);
    await tester.pumpAndSettle();

    for (final label in const [
      'All India Counselling',
      'State Counselling',
      'Filter',
      'Colleges',
      'CutOffs & Matchings',
      'Allotments',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    expect(
      find.text('We couldn’t find any colleges matching your search.'),
      findsOneWidget,
    );
  });
}

Widget _homeApp() {
  final client = MockClient(
    (_) async => http.Response(
      '{"status":true,"data":{"results":[]}}',
      200,
      headers: const {'content-type': 'application/json'},
    ),
  );
  addTearDown(client.close);
  final sessionStore = _TestSessionStore();
  return MaterialApp(
    home: HomeShell(
      apiRepository: CollegeGuideApiRepository(
        client: client,
        sessionStore: sessionStore,
        baseUrl: 'https://test.collegebook.app/api/v1/',
      ),
      sessionStore: sessionStore,
    ),
  );
}

class _TestSessionStore implements SessionStore {
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

  @override
  Future<void> clear() async {}

  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {}
}
