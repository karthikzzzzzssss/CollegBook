import AVFoundation
import CallKit
import Flutter
import PushKit
import Security
import UIKit

/// Mentor incoming consultation calls on iOS — the counterpart of the Android
/// CollegeBookFirebaseMessagingService + IncomingCounsellorConsultationActivity.
///
/// The server sends a VoIP push (topic <bundle id>.voip) with
/// `type` COUNSELLOR_NEW_REQUEST (`session_id`, `user_name`) or
/// COUNSELLOR_CALL_MISSED. iOS requires every VoIP push to be reported to
/// CallKit at once, so CallKit rings the phone; Flutter shows the
/// Android-style screens on top while the app is open
/// (lib/features/mentor/incoming_consultation.dart).
///
/// Declining (or the 30s timeout) works with the app closed: the reject call
/// is made here with the login Flutter hands over (setCallAuth).
final class ConsultationCalls: NSObject {
  /// Set once the Flutter engine is up; events wait in [pending] until
  /// Flutter says it is listening.
  var channel: FlutterMethodChannel?
  let auth = CallAuthStore()

  private let registry = PKPushRegistry(queue: .main)
  private let provider: CXProvider
  private let controller = CXCallController()
  private var calls: [UUID: Call] = [:]
  private var pending: [(String, Any?)] = []
  private var listening = false

  private static let tokenKey = "collegebook.voipToken"
  private static let ringSeconds: TimeInterval = 30

  private final class Call {
    let sessionId: String
    let userName: String?
    var answered = false
    /// Answered or declined on the Flutter screen: no API call from here.
    var handledInApp = false
    var timeout: Timer?

    init(sessionId: String, userName: String?) {
      self.sessionId = sessionId
      self.userName = userName
    }
  }

  override init() {
    let config = CXProviderConfiguration()
    config.supportsVideo = true
    config.maximumCallGroups = 1
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    config.includesCallsInRecents = false
    provider = CXProvider(configuration: config)
    super.init()
    provider.setDelegate(self, queue: .main)
  }

  func start() {
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
  }

  /// The PushKit token as hex, once iOS has issued one.
  var voipToken: String? { UserDefaults.standard.string(forKey: Self.tokenKey) }

  // MARK: Flutter

  func flutterListening() {
    listening = true
    let queued = pending
    pending.removeAll()
    for (method, args) in queued { channel?.invokeMethod(method, arguments: args) }
  }

  private func send(_ method: String, _ args: Any? = nil) {
    if listening, let channel {
      channel.invokeMethod(method, arguments: args)
    } else {
      pending.append((method, args))
    }
  }

  private func emit(_ event: String, _ call: Call) {
    NSLog("ConsultationCalls: event %@ (Flutter listening: %d)", event, listening ? 1 : 0)
    var args: [String: Any] = ["event": event, "session_id": call.sessionId]
    if let name = call.userName { args["user_name"] = name }
    send("callKitEvent", args)
  }

  /// Accepted on the Flutter screen: stop the system screen ringing.
  func answeredInApp(sessionId: String) {
    guard let (uuid, call) = find(sessionId), !call.answered else { return }
    call.handledInApp = true
    controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { _ in }
  }

  /// Declined on the Flutter screen, or the video call is over.
  func endedInApp(sessionId: String) {
    guard let (uuid, call) = find(sessionId) else { return }
    call.handledInApp = true
    controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
      // Already gone from CallKit: just forget it.
      if error != nil { self?.forget(uuid) }
    }
  }

  private func find(_ sessionId: String) -> (UUID, Call)? {
    calls.first { $0.value.sessionId == sessionId }.map { ($0.key, $0.value) }
  }

  private func forget(_ uuid: UUID) {
    calls.removeValue(forKey: uuid)?.timeout?.invalidate()
  }

  // MARK: Pushes

  /// The push's fields: at the top level or under "data" (FCM-style).
  private static func fields(_ payload: [AnyHashable: Any]) -> [String: String] {
    var out: [String: String] = [:]
    var sources: [[AnyHashable: Any]] = [payload]
    if let data = payload["data"] as? [AnyHashable: Any] { sources.append(data) }
    for source in sources {
      for (key, value) in source {
        guard let key = key as? String else { continue }
        if let s = value as? String { out[key] = s } else if let n = value as? NSNumber {
          out[key] = n.stringValue
        }
      }
    }
    return out
  }

  /// Reports the push to CallKit (iOS requires it for every VoIP push).
  func handlePush(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
    let data = Self.fields(payload)
    let sessionId = data["session_id"] ?? ""
    let type = data["type"] ?? ""
    let name = data["user_name"].flatMap { $0.isEmpty ? nil : $0 }
    NSLog("ConsultationCalls: push type=%@ session=%@", type, sessionId)

    if type == "COUNSELLOR_CALL_MISSED" {
      if let (uuid, call) = find(sessionId) {
        provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
        forget(uuid)
        emit("ended", call)
        completion()
      } else {
        reportAndEnd(completion)
      }
      return
    }
    guard !sessionId.isEmpty else {
      reportAndEnd(completion)
      return
    }
    if let (_, call) = find(sessionId), call.answered {
      // A repeat push for a call already in progress.
      reportAndEnd(completion)
      return
    }

    let uuid = find(sessionId)?.0 ?? UUID()
    let call = calls[uuid] ?? Call(sessionId: sessionId, userName: name)
    calls[uuid] = call
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: name ?? "Student")
    update.localizedCallerName = name ?? "Student"
    update.hasVideo = true
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.supportsDTMF = false
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      defer { completion() }
      guard let self else { return }
      NSLog("ConsultationCalls: reported to CallKit, error=%@", String(describing: error))
      if error != nil {
        // Do Not Disturb, blocked, or already ringing for this session.
        if self.calls[uuid]?.timeout == nil { self.forget(uuid) }
        return
      }
      call.timeout?.invalidate()
      call.timeout = Timer.scheduledTimer(withTimeInterval: Self.ringSeconds, repeats: false) {
        [weak self] _ in self?.ringTimedOut(uuid)
      }
      self.emit("incoming", call)
    }
  }

  #if DEBUG
  /// The simulator has no system call screen (CallKit ends every call it is
  /// given), so a debug ring there goes straight to the Flutter screen.
  func debugRing(sessionId: String, userName: String) {
    #if targetEnvironment(simulator)
    let uuid = UUID()
    let call = Call(sessionId: sessionId, userName: userName)
    calls[uuid] = call
    call.timeout = Timer.scheduledTimer(withTimeInterval: Self.ringSeconds, repeats: false) {
      [weak self] _ in self?.ringTimedOut(uuid)
    }
    emit("incoming", call)
    #else
    handlePush(
      ["type": "COUNSELLOR_NEW_REQUEST", "session_id": sessionId, "user_name": userName]) {}
    #endif
  }
  #endif

  /// Like the Android 30s auto-decline: unanswered → reject.
  private func ringTimedOut(_ uuid: UUID) {
    guard let call = calls[uuid], !call.answered else { return }
    provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
    forget(uuid)
    if !call.handledInApp { reject(call.sessionId) }
    emit("declined", call)
  }

  /// A push that isn't a new call still has to show on CallKit: report a call
  /// and end it straight away.
  private func reportAndEnd(_ completion: @escaping () -> Void) {
    let uuid = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "CollegeBook")
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
      self?.provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
      completion()
    }
  }

  // MARK: API (app may be closed)

  private func reject(_ sessionId: String) {
    guard let request = auth.request("college/call/\(sessionId)/reject/") else { return }
    URLSession.shared.dataTask(with: request).resume()
  }
}

// MARK: - PushKit

extension ConsultationCalls: PKPushRegistryDelegate {
  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType
  ) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    guard token != voipToken else { return }
    UserDefaults.standard.set(token, forKey: Self.tokenKey)
    send("voipTokenUpdated")
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    UserDefaults.standard.removeObject(forKey: Self.tokenKey)
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType, completion: @escaping () -> Void
  ) {
    guard type == .voIP else { return completion() }
    handlePush(payload.dictionaryPayload, completion: completion)
  }
}

// MARK: - CallKit

extension ConsultationCalls: CXProviderDelegate {
  func providerDidReset(_ provider: CXProvider) {
    for uuid in Array(calls.keys) { forget(uuid) }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let call = calls[action.callUUID] else { return action.fail() }
    call.answered = true
    call.timeout?.invalidate()
    action.fulfill()
    // Flutter accepts (API + video call); it already did if it asked for this.
    if !call.handledInApp { emit("answered", call) }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = calls[action.callUUID] else { return action.fulfill() }
    forget(action.callUUID)
    action.fulfill()
    guard !call.handledInApp else { return }
    if call.answered {
      // Hung up on the system screen during the call: Flutter ends it.
      emit("hungUp", call)
    } else {
      reject(call.sessionId)
      emit("declined", call)
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}

/// The login Flutter hands over (setCallAuth), in the keychain so a push can
/// use it with the phone locked (after the first unlock).
final class CallAuthStore {
  private let service = "collegebook.callAuth"

  func save(access: String?, refresh: String?, baseUrl: String?) {
    guard let access, !access.isEmpty else { return clear() }
    let value: [String: String] = [
      "access": access, "refresh": refresh ?? "", "baseUrl": baseUrl ?? "",
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    clear()
    let item: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: data,
    ]
    SecItemAdd(item as CFDictionary, nil)
  }

  func clear() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func load() -> [String: String]? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
      let data = out as? Data
    else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: String]
  }

  /// An authorised POST to [path] under the API root, if logged in.
  func request(_ path: String) -> URLRequest? {
    guard let saved = load(), let access = saved["access"], !access.isEmpty,
      let base = URL(string: saved["baseUrl"] ?? ""),
      let url = URL(string: path, relativeTo: base)
    else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data("{}".utf8)
    return request
  }
}
