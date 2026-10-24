import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android-side helpers in `MainActivity.kt` that keep behaviour identical to
/// the native app.
const _channel = MethodChannel('collegebook/platform');

// Widget tests run with no Android host behind the channel.
bool get _isAndroid =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    !Platform.environment.containsKey('FLUTTER_TEST');

/// iOS has no `MainActivity` channel; notification permission goes through
/// permission_handler (UNUserNotificationCenter) there instead.
bool get _isIOS =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.iOS &&
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

/// Whether the iOS system notification prompt was shown since the app
/// started, so Home doesn't follow a fresh "Don't Allow" with its own ask.
bool notificationPromptShownThisRun = false;

/// Like the native `withNotificationPermission`: on Android 13+ asks for
/// POST_NOTIFICATIONS while it isn't granted, and completes once the user has
/// answered. Returns whether notifications are allowed; callers continue
/// either way.
Future<bool> requestNotificationPermission() async {
  if (_isIOS) {
    // Only unanswered prompts actually appear; once answered, iOS stays quiet.
    if ((await Permission.notification.status).isDenied) {
      notificationPromptShownThisRun = true;
    }
    return (await Permission.notification.request()).isGranted;
  }
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

Future<T?> _invoke<T>(
  String method, [
  Map<String, Object?>? arguments,
  bool alsoIOS = false,
]) async {
  if (!_isAndroid && !(alsoIOS && _isIOS)) return null;
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

/// iOS: the PushKit VoIP token the mentor call pushes go to (AppDelegate),
/// null until iOS has issued one. Elsewhere null.
Future<String?> voipToken() async {
  if (!_isIOS) return null;
  return _invoke<String>('voipToken', null, true);
}

/// FcmTokenHelper.notificationsEnabled(): permission granted and the app's
/// notifications switched on in phone settings.
Future<bool> notificationsEnabled() async {
  if (_isIOS) {
    final status = await Permission.notification.status;
    return status.isGranted || status.isProvisional;
  }
  return await _invoke<bool>('notificationsEnabled') ?? false;
}

/// FcmTokenHelper.needsPermission(): Android 13+ and POST_NOTIFICATIONS not
/// granted yet. On iOS: the system prompt hasn't been answered yet.
Future<bool> needsNotificationPermission() async {
  if (_isIOS) return (await Permission.notification.status).isDenied;
  return await _invoke<bool>('needsNotificationPermission') ?? false;
}

/// Whether Android would still show the notification prompt after a denial.
/// iOS only ever shows it once, before it is answered.
Future<bool> shouldShowNotificationRationale() async {
  if (_isIOS) return (await Permission.notification.status).isDenied;
  return await _invoke<bool>('shouldShowNotificationRationale') ?? false;
}

/// The app's notification settings page.
Future<void> openNotificationSettings() async {
  if (_isIOS) {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      await openAppSettings();
    } on PlatformException {
      await openAppSettings();
    }
    return;
  }
  await _invoke<void>('openNotificationSettings');
}

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
}, true);

Future<void> clearCallAuth() => _invoke<void>('clearCallAuth', null, true);

// ---- iOS CallKit (AppDelegate): mentor incoming consultation calls ----

/// What CallKit tells the app about a consultation call.
enum CallKitEvent {
  /// A VoIP push rang ({session_id, user_name}).
  incoming,

  /// Answered on the system call screen ({session_id, user_name}).
  answered,

  /// Declined on the system call screen; AppDelegate already sent reject.
  declined,

  /// The student cancelled or the call was missed (COUNSELLOR_CALL_MISSED).
  ended,

  /// Hung up on the system call screen during the video call.
  hungUp,
}

/// Starts delivering CallKit events; the AppDelegate replays any that came
/// before Flutter was listening (a push that launched the app).
/// [onVoipToken] runs when iOS issues a new PushKit token.
void listenToCallKit(
  void Function(CallKitEvent event, String sessionId, String? userName)
  onEvent, {
  required void Function() onVoipToken,
}) {
  if (!_isIOS) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'voipTokenUpdated') return onVoipToken();
    if (call.method != 'callKitEvent') return;
    final args = Map<String, Object?>.from(call.arguments as Map);
    final event = CallKitEvent.values.asNameMap()['${args['event']}'];
    final sessionId = '${args['session_id'] ?? ''}';
    if (event == null || sessionId.isEmpty) return;
    onEvent(event, sessionId, args['user_name'] as String?);
  });
  _invoke<void>('callKitListening', null, true);
}

/// Tells CallKit the app answered or declined [sessionId] itself, so the
/// system call screen stops ringing (AppDelegate sends no API call for it).
Future<void> callKitAnswered(String sessionId) =>
    _invoke<void>('callKitAnswered', {'session_id': sessionId}, true);

/// Ends the CallKit call for [sessionId]: declined in the app, or the video
/// call is over.
Future<void> callKitEnd(String sessionId) =>
    _invoke<void>('callKitEnd', {'session_id': sessionId}, true);

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
