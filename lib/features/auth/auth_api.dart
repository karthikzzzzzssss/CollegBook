import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CollegeGuideApiConfig {
  const CollegeGuideApiConfig._();

  static const _developmentBaseUrl = 'https://dev.collegebook.app/api/v1/';
  static const _productionBaseUrl = 'https://api.collegebook.app/api/v1/';
  static const _configuredBaseUrl = String.fromEnvironment(
    'COLLEGE_GUIDE_API_BASE_URL',
  );

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    return kReleaseMode ? _productionBaseUrl : _developmentBaseUrl;
  }
}

class AuthApiException implements Exception {
  const AuthApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthApiResponse {
  const AuthApiResponse({
    this.status,
    this.message,
    this.description,
    this.accessToken,
    this.refreshToken,
    this.profileName,
    this.profilePhone,
  });

  final bool? status;
  final String? message;
  final String? description;
  final String? accessToken;
  final String? refreshToken;

  /// data.profile on LOGIN_SUCCESS and PROFILE_CREATED.
  final String? profileName;
  final String? profilePhone;

  factory AuthApiResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final dataMap = data is Map<String, dynamic> ? data : const {};
    final profile = dataMap['profile'];
    final profileMap = profile is Map<String, dynamic> ? profile : const {};

    return AuthApiResponse(
      status: json['status'] is bool ? json['status'] as bool : null,
      message: _stringValue(json['message']),
      description: _stringValue(json['description']),
      accessToken: _stringValue(dataMap['access']),
      refreshToken: _stringValue(dataMap['refresh']),
      profileName: _stringValue(profileMap['name']),
      profilePhone: _stringValue(profileMap['phone_number']),
    );
  }

  static String? _stringValue(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

class AuthRepository {
  AuthRepository({
    http.Client? client,
    String? baseUrl,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? CollegeGuideApiConfig.baseUrl,
       _ownsClient = client == null;

  final http.Client _client;
  final String _baseUrl;
  final Duration requestTimeout;
  final bool _ownsClient;
  bool _isClosed = false;

  Future<AuthApiResponse> requestOtp(String phoneNumber) {
    return _post('auth/login/', {'phone_number': phoneNumber});
  }

  Future<AuthApiResponse> verifyOtp({
    required String phoneNumber,
    required String otp,
    String? fcmToken,
  }) {
    return _post('auth/login/', {
      'phone_number': phoneNumber,
      'otp': otp,
      ..._deviceFields(fcmToken),
    });
  }

  Future<AuthApiResponse> register({
    required String phoneNumber,
    required String name,
    String? fcmToken,
  }) {
    return _post('auth/register/', {
      'phone_number': phoneNumber,
      'name': name,
      ..._deviceFields(fcmToken),
    });
  }

  /// FcmTokenHelper.addDeviceFields(): "registration_id" + "device_type",
  /// only when there is a token (notifications on).
  static Map<String, String> _deviceFields(String? fcmToken) =>
      fcmToken == null || fcmToken.isEmpty
      ? const {}
      : {'registration_id': fcmToken, 'device_type': 'android'};

  /// Best effort, like the native logout(): the caller clears the session
  /// whatever this answers.
  Future<void> logout({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _client
        .post(
          Uri.parse(_baseUrl).resolve('auth/logout/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({'refresh': ?refreshToken}),
        )
        .timeout(requestTimeout);
  }

  Future<AuthApiResponse> _post(
    String endpoint,
    Map<String, String> body,
  ) async {
    if (_isClosed) {
      throw const AuthApiException('The sign-in service is unavailable.');
    }

    final uri = Uri.parse(_baseUrl).resolve(endpoint);
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return _decode(response);
    } on SocketException {
      throw const AuthApiException(
        'Could not connect. Check your internet connection and try again.',
      );
    } on TimeoutException {
      throw const AuthApiException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const AuthApiException(
        'Could not connect to the sign-in service. Please try again.',
      );
    }
  }

  AuthApiResponse _decode(http.Response response) {
    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const AuthApiException(
        'The sign-in service returned an invalid response.',
      );
    }

    if (payload is! Map<String, dynamic>) {
      throw const AuthApiException(
        'The sign-in service returned an invalid response.',
      );
    }

    final parsed = AuthApiResponse.fromJson(payload);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthApiException(
        parsed.description ??
            _stringValue(payload['detail']) ??
            'Sign-in failed. Please try again.',
      );
    }

    return parsed;
  }

  String? _stringValue(Object? value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  void close() {
    if (!_ownsClient || _isClosed) return;
    _isClosed = true;
    _client.close();
  }
}
