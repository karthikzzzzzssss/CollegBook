import SwiftUI

@main
struct CollegeBookApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var app = AppState()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(app)
    }
  }
}

/// lib/app.dart: splash, then Home with a saved session, else Login.
struct RootView: View {
  @EnvironmentObject private var app: AppState

  var body: some View {
    ZStack {
      switch app.route {
      case .splash: SplashView()
      case .login: LoginView().transition(.opacity)
      case .home: HomeShellView().transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: app.route)
    .onAppear { app.installToastWindow() }
  }
}
