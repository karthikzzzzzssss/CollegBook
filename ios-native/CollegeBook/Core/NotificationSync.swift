import UIKit
import UserNotifications

/// lib/core/notification_sync.dart: keeps the backend's copy of this device's
/// push token (auth/fcm-token/) current. Mentor calls come as VoIP pushes,
/// which need no notification permission, so the PushKit token is sent
/// whenever it is new; without notifications Home asks at most once a day.
@MainActor
enum NotificationSync {
  /// Per server, so a build pointed at another API (dev ↔ production) sends
  /// the token there too instead of assuming it already has it.
  private static let sentToken = "notification_sync_sent_token." + (APIConfig.baseURL.host ?? "")
  private static let lastAskDay = "notification_sync_last_ask_day"
  private static let defaults = UserDefaults.standard

  /// Sends the VoIP token if the server doesn't have it yet.
  static func syncIfNeeded() async {
    guard let voip = ConsultationCalls.shared.voipToken, !voip.isEmpty,
      defaults.string(forKey: sentToken) != voip
    else { return }
    do {
      try await APIClient.shared.request("POST", "auth/fcm-token/", body: AuthAPI.deviceFields(voipToken: voip))
      defaults.set(voip, forKey: sentToken)
    } catch {
      // Retried on the next resume.
    }
  }

  /// CollegeHomePageActivity.checkNotificationsAndSyncToken(), run each time
  /// Home comes up.
  static func checkAndSync(promptShownThisRun: Bool) async {
    await syncIfNeeded()
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return
    case .notDetermined:
      guard shouldAskToday() else { return }
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    default:
      // Just answered the system prompt (at login): try again another day.
      guard !promptShownThisRun, shouldAskToday() else { return }
      let turnOn = await NativeAlert.show(
        title: "Turn on notifications",
        message: "Get counselling updates, call alerts and important announcements from CollegeBook.",
        negative: "Not now", positive: "Turn on")
      // This app's Notifications page (iOS 16+), else its Settings page.
      let page: String
      if #available(iOS 16, *), !Compat.legacy {
        page = UIApplication.openNotificationSettingsURLString
      } else {
        page = UIApplication.openSettingsURLString
      }
      if turnOn, let url = URL(string: page) {
        await UIApplication.shared.open(url)
      }
    }
  }

  /// True at most once per calendar day — and records that we asked today.
  private static func shouldAskToday() -> Bool {
    let format = DateFormatter()
    format.dateFormat = "yyyyMMdd"
    let today = format.string(from: Date())
    if defaults.string(forKey: lastAskDay) == today { return false }
    defaults.set(today, forKey: lastAskDay)
    return true
  }

  /// On logout: forget what was sent so the next user's token is sent fresh.
  static func clear() {
    for key in [sentToken, lastAskDay] { defaults.removeObject(forKey: key) }
  }
}
