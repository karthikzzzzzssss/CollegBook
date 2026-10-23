import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/native_bridge.dart';
import 'auth_api.dart';

abstract interface class SessionStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> saveTokens({required String accessToken, String? refreshToken});
  Future<void> clear();

  /// Like the native SessionManager.createLoginSession(): the side menu shows
  /// the saved name and number.
  Future<void> saveProfile({String? name, String? phone});
  Future<({String? name, String? phone})> readProfile();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const accessTokenKey = 'college_guide_access_token';
  static const refreshTokenKey = 'college_guide_refresh_token';
  static const nameKey = 'college_guide_profile_name';
  static const phoneKey = 'college_guide_profile_phone';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: accessTokenKey);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: refreshTokenKey);

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: refreshTokenKey, value: refreshToken);
    } else {
      await _storage.delete(key: refreshTokenKey);
    }
    await mirrorToNative();
  }

  /// Keeps the native mentor incoming-call screens on the current login
  /// (every save, including refreshes, and at app start).
  Future<void> mirrorToNative() async {
    final access = await readAccessToken();
    if (access == null || access.isEmpty) return;
    await setCallAuth(
      access: access,
      refresh: await readRefreshToken(),
      baseUrl: CollegeGuideApiConfig.baseUrl,
    );
  }

  @override
  Future<void> clear() async {
    await clearCallAuth();
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await _storage.delete(key: nameKey);
    await _storage.delete(key: phoneKey);
  }

  @override
  Future<void> saveProfile({String? name, String? phone}) async {
    if (name != null) await _storage.write(key: nameKey, value: name);
    if (phone != null) await _storage.write(key: phoneKey, value: phone);
  }

  @override
  Future<({String? name, String? phone})> readProfile() async => (
    name: await _storage.read(key: nameKey),
    phone: await _storage.read(key: phoneKey),
  );
}
