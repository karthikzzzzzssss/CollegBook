import SwiftUI
import UserNotifications

/// Which top-level screen shows, and the app-wide toast.
@MainActor
final class AppState: ObservableObject {
  enum Route { case splash, login, home }

  @Published var route: Route = .splash
  @Published var toast: String?
  /// The system notification prompt was answered this run (at login), so
  /// Home doesn't ask again straight away.
  @Published var notificationPromptShownThisRun = false
  /// Screens pushed over the tabs; the bottom bar hides while any is up.
  @Published var coveringScreens = 0
  private var toastTask: Task<Void, Never>?
  private var toastWindow: UIWindow?

  let api = APIClient.shared
  let session = SessionStore.shared

  init() {
    NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.route == .home else { return }
        self.resetUserState()
        self.route = .login
        self.show("Your session has expired. Please log in again.")
      }
    }
  }

  /// SplashScreen → _SessionGate: a saved access token opens Home.
  func finishSplash() {
    route = session.hasSession ? .home : .login
  }

  func signedIn() {
    Moderation.shared.reload()
    route = .home
  }

  func signOut() {
    resetUserState()
    route = .login
  }

  /// What one user leaves behind, however their session ended.
  private func resetUserState() {
    session.clear()
    NotificationSync.clear()
    coveringScreens = 0
    DefaultStateStore.value = ""
    ChoiceListRepository.shared.reset()
    Moderation.shared.reload()
  }

  /// Toasts get their own window, to show over full-screen covers, sheets and
  /// call screens. It takes no touches and is never made key, so it doesn't
  /// change what topViewController finds.
  func installToastWindow() {
    guard toastWindow == nil,
      let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
    else { return }
    let window = UIWindow(windowScene: scene)
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    window.isUserInteractionEnabled = false
    let host = UIHostingController(rootView: ToastHost(app: self))
    host.view.backgroundColor = .clear
    window.rootViewController = host
    window.isHidden = false
    toastWindow = window
  }

  /// native_bridge.dart showToast(): a short message at the bottom.
  func show(_ message: String) {
    // A cancelled request's error has no message: nothing to show.
    guard !message.isEmpty else { return }
    toastTask?.cancel()
    withAnimation(.easeOut(duration: 0.2)) { toast = message }
    toastTask = Task {
      try? await Task.sleep(seconds: 2.5)
      guard !Task.isCancelled else { return }
      withAnimation(.easeIn(duration: 0.2)) { toast = nil }
    }
  }

  /// Like the native app: ask for notifications before verifying the OTP.
  func requestNotificationPermission() async {
    let center = UNUserNotificationCenter.current()
    if await center.notificationSettings().authorizationStatus == .notDetermined {
      notificationPromptShownThisRun = true
    }
    _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
  }

  /// The PushKit token ConsultationCalls stores (UserDefaults
  /// `collegebook.voipToken`), sent with login and registration.
  var voipToken: String? { ConsultationCalls.shared.voipToken }
}

/// The toast window's content.
private struct ToastHost: View {
  @ObservedObject var app: AppState

  var body: some View {
    Color.clear
      .overlay(alignment: .bottom) {
        if let toast = app.toast {
          ToastView(message: toast)
            .padding(.bottom, 110)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
      }
      .animation(.easeOut(duration: 0.2), value: app.toast)
  }
}

struct ToastView: View {
  let message: String

  var body: some View {
    Text(message)
      .font(.inter(14, .medium))
      .foregroundStyle(.white)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Color.black.opacity(0.82), in: Capsule())
      .padding(.horizontal, 24)
      .accessibilityAddTraits(.updatesFrequently)
  }
}
