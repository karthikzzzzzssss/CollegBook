import AVFoundation
import CallKit
import PushKit
import UIKit

/// What CallKit tells the app about a consultation (CallKitEvent in Flutter).
enum CallKitEvent: String {
  case incoming, answered, declined, ended, hungUp
}

/// Mentor incoming consultation calls — the counterpart of the Android
/// CollegeBookFirebaseMessagingService + IncomingCounsellorConsultationActivity.
///
/// The server sends a VoIP push (topic <bundle id>.voip) with `type`
/// COUNSELLOR_NEW_REQUEST (`session_id`, `user_name`) or
/// COUNSELLOR_CALL_MISSED. iOS requires every VoIP push to be reported to
/// CallKit at once, so CallKit rings the phone; the app shows the
/// Android-style screen on top while it is open (IncomingConsultationView).
///
/// Declining (or the 30s timeout) works with the app closed: the reject call
/// is made here with the saved login.
final class ConsultationCalls: NSObject {
  static let shared = ConsultationCalls()

  /// Set once the UI is up; events wait in `pending` until then.
  var onEvent: ((CallKitEvent, String, String?) -> Void)? {
    didSet { flush() }
  }
  /// A new PushKit token to send to the server.
  var onVoipToken: (() -> Void)?

  private let registry = PKPushRegistry(queue: .main)
  private let provider: CXProvider
  private let controller = CXCallController()
  private var calls: [UUID: Call] = [:]
  private var pending: [(CallKitEvent, String, String?, Date)] = []

  static let tokenKey = "collegebook.voipToken"
  private static let ringSeconds: TimeInterval = 30

  private final class Call {
    let sessionId: String
    let userName: String?
    var answered = false
    /// Answered or declined on the in-app screen: no API call from here.
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

  /// PushKit must be set up on every launch, including the background launch
  /// a VoIP push makes, or iOS stops delivering the pushes.
  func start() {
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
  }

  /// The PushKit token as hex, once iOS has issued one.
  var voipToken: String? { UserDefaults.standard.string(forKey: Self.tokenKey) }

  private func flush() {
    guard let onEvent else { return }
    let queued = pending
    pending.removeAll()
    // The app wasn't up to act on any of these: only each session's last event
    // says where it stands now.
    var last: [String: Int] = [:]
    for (index, item) in queued.enumerated() { last[item.1] = index }
    for (index, (event, session, name, at)) in queued.enumerated() where last[session] == index {
      switch event {
      case .answered where Date().timeIntervalSince(at) >= Self.ringSeconds:
        abandonAnswered(sessionId: session)
      case .incoming, .answered:
        onEvent(event, session, name)
      case .hungUp:
        // Answered, then hung up before the app could accept it on the server.
        reject(session)
      case .declined, .ended:
        break
      }
    }
  }

  private func emit(_ event: CallKitEvent, _ call: Call) {
    #if DEBUG
      NSLog("ConsultationCalls: event %@", event.rawValue)
    #endif
    if let onEvent {
      onEvent(event, call.sessionId, call.userName)
    } else {
      pending.append((event, call.sessionId, call.userName, Date()))
    }
  }

  /// Accepted on the in-app screen: stop the system screen ringing.
  func answeredInApp(sessionId: String) {
    guard let (uuid, call) = find(sessionId), !call.answered else { return }
    call.handledInApp = true
    controller.request(CXTransaction(action: CXAnswerCallAction(call: uuid))) { _ in }
  }

  /// Declined on the in-app screen, or the video call is over.
  func endedInApp(sessionId: String) {
    guard let (uuid, call) = find(sessionId) else { return }
    call.handledInApp = true
    controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
      // Already gone from CallKit: just forget it.
      if error != nil { self?.forget(uuid) }
    }
  }

  /// Answered on the system screen but never opened in time: the student has
  /// gone, so end the system call and tell the server.
  func abandonAnswered(sessionId: String) {
    if let (uuid, _) = find(sessionId) {
      provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
      forget(uuid)
    }
    reject(sessionId)
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
        if let s = value as? String { out[key] = s } else if let n = value as? NSNumber { out[key] = n.stringValue }
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
    #if DEBUG
      NSLog("ConsultationCalls: push type=%@ session=%@", type, sessionId)
    #endif

    if type == "COUNSELLOR_CALL_MISSED" {
      if let (uuid, call) = find(sessionId) {
        provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
        forget(uuid)
        emit(.ended, call)
        completion()
      } else {
        reportAndEnd(completion)
      }
      return
    }
    guard !sessionId.isEmpty else { return reportAndEnd(completion) }
    if let (_, call) = find(sessionId), call.answered {
      // A repeat push for a call already in progress.
      return reportAndEnd(completion)
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
      if error != nil {
        // Do Not Disturb, blocked, or already ringing for this session.
        if self.calls[uuid]?.timeout == nil { self.forget(uuid) }
        return
      }
      call.timeout?.invalidate()
      call.timeout = Timer.scheduledTimer(withTimeInterval: Self.ringSeconds, repeats: false) { [weak self] _ in
        self?.ringTimedOut(uuid)
      }
      self.emit(.incoming, call)
    }
  }

  #if DEBUG
    /// The simulator has no system call screen (CallKit ends every call it is
    /// given), so a debug ring there goes straight to the in-app screen.
    func debugRing(sessionId: String, userName: String) {
      #if targetEnvironment(simulator)
        let uuid = UUID()
        let call = Call(sessionId: sessionId, userName: userName)
        calls[uuid] = call
        call.timeout = Timer.scheduledTimer(withTimeInterval: Self.ringSeconds, repeats: false) { [weak self] _ in
          self?.ringTimedOut(uuid)
        }
        emit(.incoming, call)
      #else
        handlePush(["type": "COUNSELLOR_NEW_REQUEST", "session_id": sessionId, "user_name": userName]) {}
      #endif
    }
  #endif

  /// Like the Android 30s auto-decline: unanswered → reject.
  private func ringTimedOut(_ uuid: UUID) {
    guard let call = calls[uuid], !call.answered else { return }
    provider.reportCall(with: uuid, endedAt: nil, reason: .unanswered)
    forget(uuid)
    if !call.handledInApp { reject(call.sessionId) }
    emit(.declined, call)
  }

  /// A push that isn't a new call still has to show on CallKit: report a
  /// call and end it straight away.
  private func reportAndEnd(_ completion: @escaping () -> Void) {
    let uuid = UUID()
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "CollegeBook")
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
      self?.provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
      completion()
    }
  }

  /// The app may be closed: the saved login (the keychain item is readable
  /// after the first unlock), refreshed if it has expired, with background
  /// time so the request can finish.
  private func reject(_ sessionId: String) {
    guard SessionStore.shared.accessToken?.isEmpty == false else { return }
    Task { @MainActor in
      let work = BackgroundWork()
      _ = try? await APIClient.shared.request("POST", "college/call/\(sessionId)/reject/", body: [:])
      work.end()
    }
  }
}

/// Keeps the app running in the background until `end` or the system's limit.
@MainActor
private final class BackgroundWork {
  private var id = UIBackgroundTaskIdentifier.invalid

  init() {
    id = UIApplication.shared.beginBackgroundTask { [weak self] in self?.end() }
  }

  func end() {
    guard id != .invalid else { return }
    UIApplication.shared.endBackgroundTask(id)
    id = .invalid
  }
}

// MARK: - PushKit

extension ConsultationCalls: PKPushRegistryDelegate {
  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    guard token != voipToken else { return }
    UserDefaults.standard.set(token, forKey: Self.tokenKey)
    onVoipToken?()
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    UserDefaults.standard.removeObject(forKey: Self.tokenKey)
  }

  func pushRegistry(
    _ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType,
    completion: @escaping () -> Void
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
    // The app accepts (API + video call); it already did if it asked for this.
    if !call.handledInApp { emit(.answered, call) }
    // Only the answer was handled: hanging up on the system screen later still
    // has to reach the app.
    call.handledInApp = false
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = calls[action.callUUID] else { return action.fulfill() }
    forget(action.callUUID)
    action.fulfill()
    guard !call.handledInApp else { return }
    if call.answered {
      // Hung up on the system screen during the call: the app ends it.
      emit(.hungUp, call)
    } else {
      reject(call.sessionId)
      emit(.declined, call)
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
