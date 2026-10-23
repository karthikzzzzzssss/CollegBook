import 'dart:convert';

import 'package:collegebook/features/auth/session_store.dart';
import 'package:collegebook/features/home/college_guide_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'requests college data with native query parameters and bearer token',
    () async {
      final sessionStore = _MemorySessionStore()..accessToken = 'access-token';
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return _response({
          'status': true,
          'data': {
            'results': [
              {'id': 17, 'name': 'Test Medical College'},
            ],
            'total_page': 2,
          },
        });
      });
      addTearDown(client.close);
      final repository = CollegeGuideApiRepository(
        client: client,
        sessionStore: sessionStore,
        baseUrl: 'https://test.collegebook.app/api/v1/',
      );

      final result = await repository.collegeInstitutes(
        counsellingType: 'AIC',
        page: 2,
        limit: 30,
        rank: '12345',
        category: 'OBC',
        quota: 'AI',
      );

      expect(capturedRequest?.method, 'GET');
      expect(capturedRequest?.url.path, '/api/v1/college/homepage');
      expect(capturedRequest?.url.queryParameters, {
        'query': 'institute',
        'councelling_type': 'AIC',
        'page': '2',
        'limit': '30',
        'rank': '12345',
        'category': 'OBC',
        'quota': 'AI',
      });
      expect(capturedRequest?.headers['authorization'], 'Bearer access-token');
      expect(result.items.single['name'], 'Test Medical College');
      expect(result.pagination?['total_page'], 2);
    },
  );

  test('posts mentor filters using the native request body', () async {
    final sessionStore = _MemorySessionStore()..accessToken = 'access-token';
    http.Request? capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return _response({
        'status': true,
        'data': {
          'results': [
            {'id': 8, 'name': 'Dr Example'},
          ],
        },
      });
    });
    addTearDown(client.close);
    final repository = CollegeGuideApiRepository(
      client: client,
      sessionStore: sessionStore,
      baseUrl: 'https://test.collegebook.app/api/v1/',
    );

    final result = await repository.mentors(
      states: const ['Telangana'],
      specialities: const ['Cardiology'],
      page: 1,
      limit: 20,
    );

    expect(capturedRequest?.method, 'POST');
    expect(capturedRequest?.url.path, '/api/v1/college/counsellor-list/');
    expect(jsonDecode(capturedRequest!.body), {
      'states': ['Telangana'],
      'institute_names': <String>[],
      'specialities': ['Cardiology'],
      'degrees': <String>[],
      'page': 1,
      'limit': 20,
    });
    expect(result.items.single['name'], 'Dr Example');
  });

  test(
    'refreshes expired access once and retries with the new token',
    () async {
      final sessionStore = _MemorySessionStore()
        ..accessToken = 'expired-access'
        ..refreshToken = 'refresh-token';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/token/refresh/')) {
          expect(jsonDecode(request.body), {'refresh': 'refresh-token'});
          expect(request.headers.containsKey('authorization'), isFalse);
          return _response({
            'status': true,
            'data': {'access': 'new-access', 'refresh': 'new-refresh'},
          });
        }
        if (request.headers['authorization'] == 'Bearer expired-access') {
          return _response({
            'status': false,
            'message': 'TOKEN_EXPIRED',
          }, statusCode: 401);
        }
        return _response({
          'status': true,
          'data': {
            'results': [
              {'id': 1, 'title': 'Latest update'},
            ],
          },
        });
      });
      addTearDown(client.close);
      final repository = CollegeGuideApiRepository(
        client: client,
        sessionStore: sessionStore,
        baseUrl: 'https://test.collegebook.app/api/v1/',
      );

      final result = await repository.homeNotifications();

      expect(requests, hasLength(3));
      expect(requests[0].headers['authorization'], 'Bearer expired-access');
      expect(requests[1].url.path, '/api/v1/auth/token/refresh/');
      expect(requests[2].headers['authorization'], 'Bearer new-access');
      expect(result.items.single['title'], 'Latest update');
      expect(sessionStore.accessToken, 'new-access');
      expect(sessionStore.refreshToken, 'new-refresh');
    },
  );

  test(
    'surfaces malformed response instead of showing fake empty data',
    () async {
      final client = MockClient(
        (_) async => _response({'status': true, 'data': {}}),
      );
      addTearDown(client.close);
      final repository = CollegeGuideApiRepository(
        client: client,
        sessionStore: _MemorySessionStore(),
        baseUrl: 'https://test.collegebook.app/api/v1/',
      );

      await expectLater(
        repository.reelsLanding(),
        throwsA(isA<CollegeGuideApiException>()),
      );
    },
  );
}

http.Response _response(Map<String, Object?> body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );

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
