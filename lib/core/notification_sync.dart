import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

import '../features/auth/auth_api.dart';
import '../features/home/college_guide_api.dart';
import 'native_bridge.dart';
import 'native_dialog.dart';

/// The native NotificationSync: keeps the backend's copy of this device's FCM
/// token (auth/fcm-token/) in step with whether the user can actually get
/// notifications. Mentors only get incoming-call pushes once it is there.
///  - notifications on  → send the token, but only when it's new, changed, or
///    notifications were just switched back on (no call on every app open),
///  - notifications off → never send; Home asks the user at most once a day.
class NotificationSync {
  NotificationSync(this.api, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final CollegeGuideApiRepository api;
  final FlutterSecureStorage _storage;

  static const _sentToken = 'notification_sync_sent_token';
  static const _wasEnabled = 'notification_sync_was_enabled';
  static const _lastAskDay = 'notification_sync_last_ask_day';
  static const _askedBefore = 'notification_sync_asked_permission_before';

  /// Sends the token if notifications are on and the server doesn't have it.
  Future<void> syncIfEnabled() async {
    // iOS: mentor calls come as VoIP pushes, which need no notification
    // permission, so the PushKit token is sent whenever it is new.
    final voip = await voipToken();
    if (voip != null && voip.isNotEmpty) {
      if (await _storage.read(key: _sentToken) == voip) return;
      try {
        await api.send(
          'POST',
          'auth/fcm-token/',
          body: AuthRepository.deviceFields(voipToken: voip),
        );
        await _storage.write(key: _sentToken, value: voip);
      } on CollegeGuideApiException {
        // Retried on the next resume.
      }
      return;
    }
    final enabled = await notificationsEnabled();
    final wasEnabled = await _storage.read(key: _wasEnabled) == 'true';
    await _storage.write(key: _wasEnabled, value: '$enabled');
    if (!enabled) return; // off → never send

    final token = await fcmToken();
    if (token == null) return;
    final sent = await _storage.read(key: _sentToken);
    if (wasEnabled && token == sent) return; // server already has it
    try {
      await api.send(
        'POST',
        'auth/fcm-token/',
        body: AuthRepository.deviceFields(fcmToken: token),
      );
      await _storage.write(key: _sentToken, value: token);
    } on CollegeGuideApiException {
      // Retried on the next resume.
    }
  }

  /// CollegeHomePageActivity.checkNotificationsAndSyncToken(), run each time
  /// Home comes up.
  Future<void> checkAndSync(BuildContext context) async {
    if (await notificationsEnabled()) {
      await syncIfEnabled();
      return;
    }
    await syncIfEnabled(); // records "off" so switching on later is detected
    if (!await _shouldAskToday()) return;
    // iOS: just answered the system prompt (at login) — try again another day.
    if (notificationPromptShownThisRun) return;

    final canPrompt =
        await needsNotificationPermission() &&
        (await _storage.read(key: _askedBefore) != 'true' ||
            await shouldShowNotificationRationale());
    if (canPrompt) {
      await _storage.write(key: _askedBefore, value: 'true');
      if (await requestNotificationPermission()) await syncIfEnabled();
      return;
    }
    // Below Android 13, switched off in settings, or denied twice (Android
    // won't show the prompt any more) → point the user at the settings.
    if (!context.mounted) return;
    final turnOn = await showNativeAlert(
      context,
      title: 'Turn on notifications',
      message: 'Get counselling updates, call alerts and important announcements from CollegeBook.',
      positive: 'Turn on',
      negative: 'Not now',
    );
    // Coming back triggers the resume check → the token is sent if switched on.
    if (turnOn == true) await openNotificationSettings();
  }

  /// True at most once per calendar day — and records that we asked today.
  Future<bool> _shouldAskToday() async {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    if (await _storage.read(key: _lastAskDay) == today) return false;
    await _storage.write(key: _lastAskDay, value: today);
    return true;
  }

  /// On logout: forget what was sent so the next user's token is sent fresh.
  Future<void> clear() async {
    for (final key in [_sentToken, _wasEnabled, _lastAskDay, _askedBefore]) {
      await _storage.delete(key: key);
    }
  }
}
