import FirebaseCore
import FirebaseCrashlytics
import UIKit

/// main.dart's start-up: Firebase (Crashlytics) and PushKit for
/// mentor calls.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    // PushKit must be set up on every launch, including the background launch
    // a VoIP push makes, or iOS stops delivering the pushes.
    ConsultationCalls.shared.start()
    #if DEBUG
      // `-debugIncomingCall <session id> [-debugCaller <name>]` at launch: a
      // VoIP push without APNs, which the simulator can't receive.
      if let session = UserDefaults.standard.string(forKey: "debugIncomingCall") {
        let name = UserDefaults.standard.string(forKey: "debugCaller") ?? "Test Student"
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
          ConsultationCalls.shared.debugRing(sessionId: session, userName: name)
        }
      }
      // `-debugIncomingCallScreen [-debugCaller <name>]`: present the incoming
      // consultation screen straight away, without login, for design QA.
      if UserDefaults.standard.bool(forKey: "debugIncomingCallScreen") {
        let name = UserDefaults.standard.string(forKey: "debugCaller") ?? "Tamana bhatiya"
        Task { @MainActor in
          try? await Task.sleep(seconds: 2)
          CallPresenter.present(
            IncomingConsultationView(sessionId: "preview", userName: name, autoAccept: false), app: AppState())
        }
      }
    #endif
    return true
  }
}
