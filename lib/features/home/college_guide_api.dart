import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/auth_api.dart';
import '../auth/session_store.dart';

class CollegeGuideApiException implements Exception {
  const CollegeGuideApiException(this.message, {this.statusCode, this.payload});

  final String message;

  /// The HTTP status and decoded body of a server-side failure, when there
  /// was one (screens with their own error wording read these).
  final int? statusCode;
  final Map<String, dynamic>? payload;

  @override
  String toString() => message;
}

class CollegeGuideCollection {
  const CollegeGuideCollection({
    required this.items,
    required this.raw,
    this.pagination,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> raw;
  final Map<String, dynamic>? pagination;

  factory CollegeGuideCollection.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final dataMap = data is Map<String, dynamic> ? data : null;
    final results =
        dataMap?['results'] ?? (data is List ? data : json['results']);
    if (results is! List) {
      throw const CollegeGuideApiException(
        'The CollegeBook service returned an invalid list response.',
      );
    }

    final items = <Map<String, dynamic>>[];
    for (final item in results) {
      if (item is! Map<String, dynamic>) {
        throw const CollegeGuideApiException(
          'The CollegeBook service returned an invalid list item.',
        );
      }
      items.add(item);
    }

    return CollegeGuideCollection(
      items: List.unmodifiable(items),
      raw: json,
      pagination: dataMap,
    );
  }
}

class CollegeGuideApiRepository {
  CollegeGuideApiRepository({
    http.Client? client,
    SessionStore? sessionStore,
    String? baseUrl,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _sessionStore = sessionStore ?? SecureSessionStore(),
       _baseUrl = baseUrl ?? CollegeGuideApiConfig.baseUrl,
       _ownsClient = client == null;

  final http.Client _client;
  final SessionStore _sessionStore;
  final String _baseUrl;
  final Duration requestTimeout;
  final bool _ownsClient;
  Future<String?>? _refreshInProgress;
  bool _isClosed = false;

  Future<CollegeGuideCollection> examTypes() => _getCollection('exam-types/');

  /// Saves the exam type the home screen's pill switches to; every other
  /// endpoint keys off this server-side preference.
  Future<void> updateExamType(String code) =>
      _request('PATCH', 'auth/exam-type/', body: {'exam_type': code});

  Future<CollegeGuideCollection> homeBanners() =>
      _getCollection('college/banner/');

  Future<CollegeGuideCollection> recommendedColleges() =>
      _getCollection('college/recommended-colleges/');

  Future<CollegeGuideCollection> homeHelpTools() =>
      _getCollection('college/help-tools/');

  Future<CollegeGuideCollection> homeCategories() =>
      _getCollection('ccms/categories/');

  Future<CollegeGuideCollection> abroadCountries() =>
      _getCollection('abroad/countries-list/');

  Future<CollegeGuideCollection> homeNotifications({
    int page = 1,
    int limit = 40,
  }) => _getCollection(
    'college/notifications/',
    query: {'page': '$page', 'limit': '$limit'},
  );

  Future<CollegeGuideCollection> homeEvents() =>
      _getCollection('college/skill/', query: const {'eventid': 'all'});

  Future<CollegeGuideCollection> homeRecommendedReels() =>
      _getCollection('reels/landing-recommended-reels/');

  Future<Map<String, dynamic>> collegeGuidance({required String tab}) =>
      _getObject('college/guidance', query: {'tab': tab});

  Future<CollegeGuideCollection> collegeInstitutes({
    required String counsellingType,
    int page = 1,
    int limit = 30,
    String? query,
    String? rank,
    String? category,
    String? quota,
    String? state,
    String? speciality,
  }) {
    final parameters = <String, String>{
      'query': query ?? 'institute',
      'councelling_type': counsellingType,
      'page': '$page',
      'limit': '$limit',
    };
    _addOptional(parameters, 'rank', rank);
    _addOptional(parameters, 'category', category);
    _addOptional(parameters, 'quota', quota);
    _addOptional(parameters, 'state', state);
    _addOptional(parameters, 'speciality', speciality);
    return _getCollection('college/homepage', query: parameters);
  }

  Future<CollegeGuideCollection> collegeSearch({
    required String search,
    required String query,
  }) {
    final encodedSearch = Uri.encodeComponent(search);
    return _getCollection(
      'college/search/$encodedSearch',
      query: {'search': query},
    );
  }

  Future<CollegeGuideCollection> collegeDetailsCutoffs({
    required String counsellingType,
    required String collegeId,
    int limit = 40,
  }) => _getCollection(
    'college/homepage',
    query: {
      'limit': '$limit',
      'councelling_type': counsellingType,
      'query': 'cutoff_list',
      'id': collegeId,
    },
  );

  Future<Map<String, dynamic>> collegeDetails(String collegeId) =>
      _getObject('college/details/$collegeId/');

  Future<CollegeGuideCollection> mentors({
    int page = 1,
    int limit = 20,
    List<String> states = const [],
    List<String> instituteNames = const [],
    List<String> specialities = const [],
    List<String> degrees = const [],
  }) => _postCollection('college/counsellor-list/', {
    'states': states,
    'institute_names': instituteNames,
    'specialities': specialities,
    'degrees': degrees,
    'page': page,
    'limit': limit,
  });

  Future<CollegeGuideCollection> mentorFilterOptions(String selection) =>
      _getCollection('college/counsellor/drop-down/$selection/');

  Future<CollegeGuideCollection> mentorInstitutes({String? state}) =>
      _getCollection(
        'college/counsellor/drop-down/institute_name/',
        query: {if (state != null && state.isNotEmpty) 'state': state},
      );

  Future<CollegeGuideCollection> mentorInstitutesForStates(
    List<String> states,
  ) => _postCollection('college/states/institute-list/', {'states': states});

  Future<CollegeGuideCollection> mentorFavorites({
    int page = 1,
    int limit = 20,
  }) => _getCollection(
    'college/fevorite-counsellor/',
    query: {'page': '$page', 'limit': '$limit'},
  );

  Future<CollegeGuideCollection> reelsLanding() =>
      _getCollection('reels/landing/');

  Future<CollegeGuideCollection> communityQuestions({
    required String counsellingType,
    required String state,
    int page = 1,
    int limit = 40,
  }) => _getCollection(
    'college/homepage',
    query: {
      'page': '$page',
      'limit': '$limit',
      'state': state,
      'councelling_type': counsellingType,
      'query': 'user-post',
    },
  );

  Future<CollegeGuideCollection> communityGroups() =>
      _getCollection('chat/groups/');

  Future<CollegeGuideCollection> communityGroupMessages({
    required String slug,
    int limit = 40,
    String? before,
    String? after,
  }) => _getCollection(
    'chat/groups/${Uri.encodeComponent(slug)}/messages/',
    query: {
      'limit': '$limit',
      if (before != null && before.isNotEmpty) 'before': before,
      if (after != null && after.isNotEmpty) 'after': after,
    },
  );

  Future<CollegeGuideCollection> questionComments(String questionId) =>
      _getCollection('college/question-comments/$questionId/');

  Future<CollegeGuideCollection> premiumPlans() =>
      _getCollection('college/plan/');

  Future<Map<String, dynamic>> membership() =>
      _getObject('college/membership/');

  /// The native getCollegeHome(): one page of college/homepage with the
  /// caller's filters. The returned data holds results, total_page and
  /// default_parameter.
  Future<Map<String, dynamic>> collegeHomePage({
    required int page,
    required int limit,
    required Map<String, String> params,
  }) => _getObject(
    'college/homepage',
    query: {'page': '$page', 'limit': '$limit', ...params},
  );

  /// Filter options: homeFilters(AIC|SC) and stateFilters(state_name).
  Future<Map<String, dynamic>> cutoffFilters(
    String counsellingType, {
    String? stateName,
  }) => _getObject(
    'college/dropdwon/$counsellingType',
    query: {'state_name': ?stateName},
  );

  /// The raw body of an endpoint that answers HTML (ccms/items/{id}/webview/).
  Future<String> fetchText(String endpoint) async {
    final uri = Uri.parse(_baseUrl).resolve(endpoint);
    final response = await _send(
      'GET',
      uri,
      accessToken: await _sessionStore.readAccessToken(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CollegeGuideApiException(
        'Failed to load content',
        statusCode: response.statusCode,
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// Any JSON endpoint: the decoded body (throws CollegeGuideApiException).
  Future<Map<String, dynamic>> send(
    String method,
    String endpoint, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) => _request(method, endpoint, query: query, body: body);

  // ---- Choice lists (college/collections/) ----

  Future<Map<String, dynamic>> choiceRequest(
    String method,
    String endpoint, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) => _request(method, endpoint, query: query, body: body);

  /// A server-rendered page under the API root (the native WebViews).
  Uri webPage(String path, [Map<String, String> query = const {}]) {
    final uri = Uri.parse(_baseUrl).resolve(path);
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  /// The API host, for keeping WebView navigation to it authenticated.
  String get apiHost => Uri.parse(_baseUrl).host;

  /// Bearer headers for a WebView request; loadUrl() sends none by itself.
  Future<Map<String, String>> authHeaders() async {
    final token = await _sessionStore.readAccessToken();
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// The saved login token (the call socket carries it in its URL).
  Future<String?> accessToken() => _sessionStore.readAccessToken();

  /// A multipart POST (the chat's text + files). Answers the HTTP status and
  /// the decoded JSON body, if any — the chat reads its own error codes.
  Future<({int status, Map<String, dynamic>? json})> postMultipart(
    String endpoint, {
    Map<String, String> fields = const {},
    List<http.MultipartFile> files = const [],
  }) async {
    Future<http.Response> attempt(String? token) async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_baseUrl).resolve(endpoint),
      );
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields.addAll(fields);
      request.files.addAll(files);
      try {
        final streamed = await request.send().timeout(
          const Duration(seconds: 90),
        );
        return await http.Response.fromStream(streamed);
      } on SocketException {
        throw const CollegeGuideApiException(
          'Could not connect. Check your internet connection and try again.',
        );
      } on TimeoutException {
        throw const CollegeGuideApiException(
          'The server took too long to respond. Please try again.',
        );
      } on http.ClientException {
        throw const CollegeGuideApiException(
          'Could not connect to the CollegeBook service. Please try again.',
        );
      }
    }

    final token = await _sessionStore.readAccessToken();
    var response = await attempt(token);
    if (token != null &&
        response.statusCode >= 400 &&
        response.body.contains('TOKEN_EXPIRED')) {
      try {
        final refreshed = await _refreshAfterExpiry();
        if (refreshed != null) response = await attempt(refreshed);
      } on CollegeGuideApiException {
        // Answer the original failure.
      }
    }
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      json = null;
    }
    return (status: response.statusCode, json: json);
  }

  Future<Map<String, dynamic>> walletBalance() => _getObject('auth/wallet/');

  String resolveMediaUrl(String path) {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) return uri.toString();
    final base = Uri.parse(_baseUrl);
    final origin = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
    );
    return origin.resolve(path.startsWith('/') ? path : '/$path').toString();
  }

  Future<CollegeGuideCollection> _getCollection(
    String endpoint, {
    Map<String, String> query = const {},
  }) async => CollegeGuideCollection.fromJson(
    await _request('GET', endpoint, query: query),
  );

  Future<CollegeGuideCollection> _postCollection(
    String endpoint,
    Map<String, Object?> body,
  ) async => CollegeGuideCollection.fromJson(
    await _request('POST', endpoint, body: body),
  );

  Future<Map<String, dynamic>> _getObject(
    String endpoint, {
    Map<String, String> query = const {},
  }) async {
    final json = await _request('GET', endpoint, query: query);
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    if (data == null) return json;
    throw const CollegeGuideApiException(
      'The CollegeBook service returned an invalid object response.',
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    if (_isClosed) {
      throw const CollegeGuideApiException(
        'The CollegeBook service is unavailable.',
      );
    }

    final uri = Uri.parse(_baseUrl)
        .resolve(endpoint)
        .replace(queryParameters: query.isEmpty ? null : query);
    final accessToken = await _sessionStore.readAccessToken();
    final response = await _send(
      method,
      uri,
      accessToken: accessToken,
      body: body,
    );

    if (accessToken != null &&
        response.statusCode >= 400 &&
        response.body.contains('TOKEN_EXPIRED')) {
      final currentToken = await _sessionStore.readAccessToken();
      String? refreshedToken;
      var refreshFailed = false;
      if (currentToken != null && currentToken != accessToken) {
        refreshedToken = currentToken;
      } else {
        try {
          refreshedToken = await _refreshAfterExpiry();
        } on CollegeGuideApiException {
          refreshFailed = true;
          await _sessionStore.clear();
        }
      }
      if (refreshedToken != null) {
        return _decodeResponse(
          await _send(method, uri, accessToken: refreshedToken, body: body),
        );
      }
      if (!refreshFailed) {
        await _sessionStore.clear();
      }
    }

    return _decodeResponse(response);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required String? accessToken,
    Map<String, Object?>? body,
  }) async {
    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
      if (body != null) 'Content-Type': 'application/json',
    };
    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'PATCH' => _client.patch(uri, headers: headers, body: jsonEncode(body)),
        'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => _client.post(uri, headers: headers, body: jsonEncode(body)),
      };
      return await request.timeout(requestTimeout);
    } on SocketException {
      throw const CollegeGuideApiException(
        'Could not connect. Check your internet connection and try again.',
      );
    } on TimeoutException {
      throw const CollegeGuideApiException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const CollegeGuideApiException(
        'Could not connect to the CollegeBook service. Please try again.',
      );
    }
  }

  Future<String?> _refreshAfterExpiry() {
    final pending = _refreshInProgress;
    if (pending != null) return pending;
    final refresh = _refreshAccessToken();
    _refreshInProgress = refresh;
    return refresh.whenComplete(() => _refreshInProgress = null);
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = await _sessionStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    final uri = Uri.parse(_baseUrl).resolve('auth/token/refresh/');
    final response = await _send(
      'POST',
      uri,
      accessToken: null,
      body: {'refresh': refreshToken},
    );
    final json = _decodeResponse(response);
    final data = json['data'];
    final dataMap = data is Map<String, dynamic> ? data : null;
    final access = dataMap?['access'];
    if (access is! String || access.trim().isEmpty) {
      throw const CollegeGuideApiException(
        'The session refresh response did not contain an access token.',
      );
    }
    final updatedRefresh = dataMap?['refresh'];
    await _sessionStore.saveTokens(
      accessToken: access.trim(),
      refreshToken: updatedRefresh is String && updatedRefresh.isNotEmpty
          ? updatedRefresh
          : refreshToken,
    );
    return access.trim();
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    // A DELETE may answer 204 with no body at all.
    if (response.body.trim().isEmpty &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      return const {};
    }
    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const CollegeGuideApiException(
        'The CollegeBook service returned an invalid response.',
      );
    }

    if (payload is! Map<String, dynamic>) {
      throw const CollegeGuideApiException(
        'The CollegeBook service returned an invalid response.',
      );
    }
    final status = payload['status'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        status == false) {
      throw CollegeGuideApiException(
        _errorMessage(payload),
        statusCode: response.statusCode,
        payload: payload,
      );
    }
    return payload;
  }

  String _errorMessage(Map<String, dynamic> json) {
    for (final key in const ['description', 'detail', 'message']) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'The CollegeBook request failed. Please try again.';
  }

  void _addOptional(Map<String, String> parameters, String key, String? value) {
    if (value != null && value.isNotEmpty) parameters[key] = value;
  }

  void close() {
    if (!_ownsClient || _isClosed) return;
    _isClosed = true;
    _client.close();
  }
}
