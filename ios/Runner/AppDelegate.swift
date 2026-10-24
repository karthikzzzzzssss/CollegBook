import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let calls = ConsultationCalls()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // PushKit must be set up on every launch, including the background launch
    // a VoIP push makes, or iOS stops delivering the pushes.
    calls.start()
    #if DEBUG
    // `-debugIncomingCall <session id> [-debugCaller <name>]` at launch: a VoIP
    // push without APNs, which the simulator can't receive.
    if let session = UserDefaults.standard.string(forKey: "debugIncomingCall") {
      let name = UserDefaults.standard.string(forKey: "debugCaller") ?? "Test Student"
      DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [calls] in
        calls.debugRing(sessionId: session, userName: name)
      }
    }
    #endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The iOS side of `collegebook/platform` (lib/core/native_bridge.dart).
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CollegeBookPlatform")
    else { return }
    let channel = FlutterMethodChannel(
      name: "collegebook/platform", binaryMessenger: registrar.messenger())
    calls.channel = channel
    channel.setMethodCallHandler { [calls] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      let sessionId = args["session_id"] as? String ?? ""
      switch call.method {
      case "openNotificationSettings":
        // Straight to this app's Notifications page (iOS 16+), else its
        // Settings page.
        let target: String
        if #available(iOS 16.0, *) {
          target = UIApplication.openNotificationSettingsURLString
        } else {
          target = UIApplication.openSettingsURLString
        }
        if let url = URL(string: target) {
          UIApplication.shared.open(url)
        }
        result(nil)
      case "voipToken":
        result(calls.voipToken)
      case "setCallAuth":
        calls.auth.save(
          access: args["access"] as? String,
          refresh: args["refresh"] as? String,
          baseUrl: args["baseUrl"] as? String)
        result(nil)
      case "clearCallAuth":
        calls.auth.clear()
        result(nil)
      case "callKitListening":
        calls.flutterListening()
        result(nil)
      case "callKitAnswered":
        calls.answeredInApp(sessionId: sessionId)
        result(nil)
      case "callKitEnd":
        calls.endedInApp(sessionId: sessionId)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
