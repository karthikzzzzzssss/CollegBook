import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android-side helpers in `MainActivity.kt` that keep behaviour identical to
/// the native app.
const _channel = MethodChannel('collegebook/platform');

// Widget tests run with no Android host behind the channel.
bool get _isAndroid =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// Shows [message] the way the native app does: an Android system Toast
/// (`Toast.LENGTH_SHORT`), so it looks right on every Android version. iOS has
/// no system toast, so there (and wherever the channel is missing, such as in
/// widget tests) a toast-like floating message is shown instead.
Future<void> showToast(BuildContext context, String message) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (_isAndroid) {
    try {
      await _channel.invokeMethod<void>('showToast', {'message': message});
      return;
    } on MissingPluginException {
      // Fall through to the in-app message.
    } on PlatformException {
      // Fall through to the in-app message.
    }
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF424242),
        shape: const StadiumBorder(),
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 64),
      ),
    );
}

/// Like the native `withNotificationPermission`: on Android 13+ asks for
/// POST_NOTIFICATIONS while it isn't granted, and completes once the user has
/// answered. Returns whether notifications are allowed; callers continue
/// either way.
Future<bool> requestNotificationPermission() async {
  if (!_isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

Future<T?> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
  if (!_isAndroid) return null;
  try {
    return await _channel.invokeMethod<T>(method, arguments);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// FcmTokenHelper.fetchIfNotificationsEnabled(): the FCM token while
/// notifications are on, else null (within 5s at the latest).
Future<String?> fcmToken() => _invoke<String>('fcmToken');

/// FcmTokenHelper.notificationsEnabled(): permission granted and the app's
/// notifications switched on in phone settings.
Future<bool> notificationsEnabled() async =>
    await _invoke<bool>('notificationsEnabled') ?? false;

/// FcmTokenHelper.needsPermission(): Android 13+ and POST_NOTIFICATIONS not
/// granted yet.
Future<bool> needsNotificationPermission() async =>
    await _invoke<bool>('needsNotificationPermission') ?? false;

/// Whether Android would still show the notification prompt after a denial.
Future<bool> shouldShowNotificationRationale() async =>
    await _invoke<bool>('shouldShowNotificationRationale') ?? false;

/// The app's notification settings page.
Future<void> openNotificationSettings() =>
    _invoke<void>('openNotificationSettings');

/// Hands the login to the native mentor incoming-call screens, which act on
/// the user's behalf while the app is closed.
Future<void> setCallAuth({
  required String access,
  String? refresh,
  required String baseUrl,
}) => _invoke<void>('setCallAuth', {
  'access': access,
  'refresh': refresh,
  'baseUrl': baseUrl,
});

Future<void> clearCallAuth() => _invoke<void>('clearCallAuth');

/// Like the native `makeCallWithPermission()`: asks for CALL_PHONE if needed,
/// then places the call directly (Android). Elsewhere nothing happens.
Future<void> callNumber(String number) async {
  if (!_isAndroid) return;
  try {
    await _channel.invokeMethod<void>('callNumber', {'number': number});
  } on MissingPluginException {
    // No Android host (tests).
  } on PlatformException {
    // Nothing to fall back to.
  }
}

/// Saves [bytes] as Downloads/CollegeBook/[fileName] (Android 10+) or a
/// shareable cache file, like the native ChoiceListExporter. Returns the
/// file's content:// uri.
Future<String> saveDownload({
  required String fileName,
  required String mimeType,
  required Uint8List bytes,
}) async {
  if (!_isAndroid) {
    throw PlatformException(code: 'UNSUPPORTED', message: 'Android only');
  }
  final uri = await _channel.invokeMethod<String>('saveDownload', {
    'fileName': fileName,
    'mimeType': mimeType,
    'bytes': bytes,
  });
  if (uri == null) throw PlatformException(code: 'SAVE_FAILED');
  return uri;
}

/// Opens a saved file, falling back to the share sheet.
Future<void> openFile(String uri, String mimeType, String format) async {
  if (!_isAndroid) return;
  await _channel.invokeMethod<void>('openFile', {
    'uri': uri,
    'mimeType': mimeType,
    'format': format,
  });
}

/// Opens a web file the way the native chat does: an image straight in a
/// viewer ([mimeType] `image/*`), anything else through a chooser titled
/// [chooserTitle].
/// With [package], only that app may open it. Answers whether anything did.
Future<bool> viewUrl(
  String url, {
  String? mimeType,
  String? chooserTitle,
  String? package,
}) async {
  if (!_isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('viewUrl', {
          'url': url,
          'mimeType': mimeType,
          'chooserTitle': chooserTitle,
          'package': package,
        }) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The native DisplayMetrics.heightPixels, in physical pixels; null off
/// Android or when unknown.
Future<int?> displayHeight() async {
  if (!_isAndroid) return null;
  try {
    return await _channel.invokeMethod<int>('displayHeight');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Opens the dialer with [number] filled in (no call is placed). Answers
/// whether a dialer opened.
Future<bool> dial(String number) async {
  if (!_isAndroid) return false;
  try {
    return await _channel.invokeMethod<bool>('dial', {'number': number}) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The system share sheet for [text], titled [title].
Future<void> shareText({
  required String text,
  required String subject,
  required String title,
}) async {
  if (!_isAndroid) return;
  try {
    await _channel.invokeMethod<void>('shareText', {
      'text': text,
      'subject': subject,
      'title': title,
    });
  } on PlatformException {
    // Nothing to share with.
  } on MissingPluginException {
    // No Android host (tests).
  }
}
