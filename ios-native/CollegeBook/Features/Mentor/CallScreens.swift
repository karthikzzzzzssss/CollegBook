import SwiftUI

/// Presents call screens full screen over whatever is showing (the Flutter
/// root navigator), and closes them.
@MainActor
enum CallPresenter {
  private static var hosts: [(key: String?, host: UIViewController)] = []
  /// Screens with no foreground scene to present over yet (the session is
  /// already open): CallCoordinator.showWaiting presents them.
  private static var pending: [(key: String?, host: UIViewController)] = []

  /// `key` is the session the screen belongs to.
  static func present<V: View>(_ view: V, key: String? = nil, app: AppState) {
    let host = UIHostingController(rootView: view.environmentObject(app))
    host.modalPresentationStyle = .fullScreen
    host.isModalInPresentation = true
    host.view.backgroundColor = .black
    guard let top = Platform.topViewController() else {
      pending.append((key, host))
      return
    }
    hosts.append((key, host))
    top.present(host, animated: true)
  }

  /// Presents a screen that had to wait for a foreground scene.
  static func presentPending() {
    guard !pending.isEmpty, let top = Platform.topViewController() else { return }
    let entry = pending.removeFirst()
    hosts.append(entry)
    top.present(entry.host, animated: true)
  }

  /// A call screen is up, or waiting to be, for another session.
  static func isBusy(except key: String) -> Bool {
    (hosts + pending).contains { $0.key != key }
  }

  /// Closes the session's call screen; `then` runs once it is gone.
  static func dismiss(key: String?, then: (() -> Void)? = nil) {
    guard let index = hosts.lastIndex(where: { $0.key == key }) ?? hosts.lastIndex(where: { $0.key == nil }) else {
      then?()
      return
    }
    let host = hosts[index].host
    hosts.removeSubrange(index...)
    // Through the presenter: on the screen itself this would only close an
    // alert showing on top of it.
    guard let presenter = host.presentingViewController else {
      then?()
      return
    }
    presenter.dismiss(animated: true) { then?() }
  }
}

/// MentorCallStarter.confirmAndCall: confirm, start the call session, then
/// open the video call.
@MainActor
func confirmAndCallMentor(_ mentor: Mentor, app: AppState) async {
  let confirmed = await NativeAlert.show(
    title: "Confirm Video Call", message: "Are you sure you want to go for video call?", negative: "No",
    positive: "Yes")
  guard confirmed else { return }
  let hide = NativeAlert.progress()
  var json: JSONObject?
  var failure: String?
  do {
    json = try await app.api.request(
      "POST", "college/call/initiate/", body: ["counsellor_id": Int(mentor.id) ?? mentor.id])
  } catch let error as APIError {
    failure = error.payload.map(serverMessage) ?? "Couldn't start the call. Check your internet and try again."
  } catch {
    failure = "Couldn't start the call. Check your internet and try again."
  }
  hide()
  guard failure == nil, let data = json?.object("data") else {
    app.show(failure ?? json.map(serverMessage) ?? "")
    return
  }
  // Let the progress overlay finish dismissing before presenting.
  try? await Task.sleep(seconds: 0.35)
  let sessionId = data.string("session_id") ?? ""
  CallPresenter.present(
    StudentVideoCallView(
      sessionId: sessionId, uid: data.int("uid") ?? 0,
      channelName: data.string("channel_name") ?? "", agoraToken: data.string("agora_token") ?? ""),
    key: sessionId, app: app)
}

/// The server's text for a refused call: description, else message.
private func serverMessage(_ json: JSONObject) -> String {
  json.string(["description", "message"]) ?? "Unable to start the call. Please try again."
}

// MARK: - Student call (AgoraVideoCallActivity)

struct StudentVideoCallView: View {
  let sessionId: String
  let uid: Int
  let channelName: String
  let agoraToken: String

  @EnvironmentObject private var app: AppState
  @StateObject private var call = AgoraCall()
  @State private var socket: CallSocket?
  @State private var waitingTimer: Task<Void, Never>?
  /// When the running wait gives up; nil once the mentor has answered.
  @State private var waitDeadline: Date?
  @State private var remoteConnected = false
  @State private var connected = false
  @State private var apiCallInProgress = false
  @State private var sessionClosing = false
  @State private var finished = false
  @State private var swapped = false
  @State private var waiting = false
  @State private var remaining: String?

  var body: some View {
    ZStack {
      VideoCallLayout(call: call, swapped: $swapped, badge: connected ? nil : remaining, onBack: showExitDialog)
      if waiting {
        Color.black.opacity(0.5).ignoresSafeArea()
        WaitingDialog(onCancel: cancelFromWaiting)
      }
    }
    .task { await start() }
    .onDisappear { teardown() }
  }

  private func start() async {
    socket = CallSocket(sessionId: sessionId, role: "user") { handle($0) }
    guard await AgoraCall.requestPermissions() else {
      app.show("Camera & Audio permissions required.")
      // The session is already open and the mentor's phone is ringing.
      await endCall()
      leaveAndFinish()
      return
    }
    try? await Task.sleep(seconds: 0.3)
    guard !finished else { return }
    call.onRemoteJoined = { _ in
      stopWaitingTimer()
      remoteConnected = true
      checkBothConnected()
    }
    call.onRemoteLeft = {
      guard !finished else { return }
      remoteConnected = false
      app.show("User disconnected")
      // They may have dropped without ending it: don't leave it open.
      let alreadyEnding = apiCallInProgress || sessionClosing
      leaveAndFinish()
      if !alreadyEnding { Task { await endCall() } }
    }
    guard call.join(token: agoraToken, channel: channelName, uid: uid) else {
      app.show("Couldn't start the video call")
      await endCall()
      leaveAndFinish()
      return
    }
    checkBothConnected()
    if !connected {
      showWaiting()
      startWaitingTimer()
    }
  }

  // MARK: Call socket: waiting/accepted/balance/terminal events

  private func handle(_ message: JSONObject) {
    switch message["type"] as? String {
    case "WAITING_FOR_COUNSELLOR":
      showWaiting()
    case "CALL_ACCEPTED":
      stopWaitingTimer()
      waiting = false
    case "BALANCE_UPDATE":
      let balance = message.string("balance") ?? "0"
      remaining = "Balance: ₹\(balance)"
      if let value = Double(balance), value <= 0 {
        Task { await closeSessionAndFinish("Call ended: balance exhausted") }
      }
    case "CALL_CANCELLED", "CALL_REJECTED", "CALL_MISSED", "CALL_BALANCE_EXHAUSTED", "CALL_ENDED":
      app.show(message["body"] as? String ?? "Call ended")
      leaveAndFinish()
    default:
      break
    }
  }

  private func endCall() async {
    // The screen closes whatever the answer.
    _ = try? await app.api.request("POST", "college/call/\(sessionId)/end/", body: [:])
  }

  private func closeSessionAndFinish(_ reason: String) async {
    guard !sessionClosing else { return }
    sessionClosing = true
    app.show(reason)
    await endCall()
    leaveAndFinish()
  }

  // MARK: Waiting: shown until the mentor joins

  private func showWaiting() {
    // Not once the mentor is in: the socket and Agora can race.
    guard !finished, !connected, !remoteConnected else { return }
    waiting = true
  }

  private func cancelFromWaiting() {
    guard !apiCallInProgress else { return }
    apiCallInProgress = true
    Task {
      await endCall()
      apiCallInProgress = false
      leaveAndFinish()
    }
  }

  /// Cancel (waiting) or end (connected).
  private func showExitDialog() {
    guard !apiCallInProgress else { return }
    let isConnected = connected
    // Paused while the alert is up; Stay picks it up again below.
    waitingTimer?.cancel()
    Task {
      let confirmed = await NativeAlert.show(
        title: isConnected ? "End Call?" : "Cancel Call?",
        message: isConnected
          ? "Are you sure you want to end this call?" : "Are you sure you want to cancel the call request?",
        negative: "Stay", positive: isConnected ? "End" : "Cancel Call", destructive: true)
      guard confirmed, !apiCallInProgress else {
        if waitDeadline != nil, !finished, !apiCallInProgress { startWaitingTimer() }
        return
      }
      apiCallInProgress = true
      await endCall()
      apiCallInProgress = false
      leaveAndFinish()
    }
  }

  private func checkBothConnected() {
    guard call.localConnected, remoteConnected else { return }
    waiting = false
    app.show("Both connected successfully")
    stopWaitingTimer()
    connected = true
    remaining = nil
  }

  /// Auto-cancel when the mentor doesn't join within the 30s they're rung for.
  private func startWaitingTimer() {
    let deadline = waitDeadline ?? Date().addingTimeInterval(30)
    waitDeadline = deadline
    waitingTimer?.cancel()
    waitingTimer = Task {
      try? await Task.sleep(seconds: deadline.timeIntervalSinceNow)
      guard !Task.isCancelled, !remoteConnected, !apiCallInProgress, !finished else { return }
      app.show("No response. Cancelling call...")
      apiCallInProgress = true
      await endCall()
      leaveAndFinish()
    }
  }

  private func stopWaitingTimer() {
    waitingTimer?.cancel()
    waitDeadline = nil
  }

  /// Leaves the channel and goes back to the app.
  private func leaveAndFinish() {
    guard !finished else { return }
    finished = true
    teardown()
    CallPresenter.dismiss(key: sessionId)
  }

  private func teardown() {
    waitingTimer?.cancel()
    socket?.close()
    socket = nil
    call.leave()
  }
}

/// dialog_waiting_doctor.xml.
private struct WaitingDialog: View {
  let onCancel: () -> Void
  @State private var pulse = false

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Circle().fill(Color(hex: 0x007BFF, alpha: 0.2)).frame(width: 90, height: 90)
          .scaleEffect(pulse ? 1.35 : 1).opacity(pulse ? 0 : 0.6)
        Circle().fill(Color(hex: 0x007BFF, alpha: 0.2)).frame(width: 64, height: 64)
        Image("home_iv_mirror").renderingMode(.template).resizable().frame(width: 32, height: 32).foregroundStyle(.white)
      }
      .frame(width: 90, height: 90)
      .onAppear {
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
      }
      Text("Connecting you to the Mentor").font(.inter(17, .bold)).foregroundStyle(.black).padding(.top, 20)
      Text("Please hold on, your mentor will join shortly").font(.inter(13)).foregroundStyle(Color(hex: 0x888888))
        .multilineTextAlignment(.center).padding(.top, 6)
      ProgressView().tint(appInk).padding(.top, 18)
      Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 1).padding(.top, 20).padding(.bottom, 12)
      Button(action: onCancel) {
        Text("Cancel Request").font(.inter(14, .bold)).foregroundStyle(Color(hex: 0xF44336))
          .frame(maxWidth: .infinity).frame(height: 44)
          .background(Color(hex: 0xFFF0F0), in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
    }
    .padding(28)
    .frame(width: UIScreen.main.bounds.width * 0.85)
    .background(.white, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xC5C5C5)))
  }
}

// MARK: - Mentor's side (CounsellorVideoCallActivity)

/// The mentor's side of an accepted consultation: the same screen on the
/// counsellor socket. It ends on the mentor's request (end API), when the
/// student leaves, or when the call socket says the call is over.
struct CounsellorVideoCallView: View {
  let sessionId: String
  let uid: Int
  let channelName: String
  let agoraToken: String

  @EnvironmentObject private var app: AppState
  @StateObject private var call = AgoraCall()
  @State private var socket: CallSocket?
  @State private var swapped = false
  @State private var sessionEnded = false
  @State private var forceClosing = false
  @State private var finished = false

  /// The `data` of college/call/{id}/accept/.
  init(sessionId: String, accept data: JSONObject) {
    self.sessionId = data.string("session_id") ?? sessionId
    uid = data.int("uid") ?? 0
    channelName = data.string("channel_name") ?? ""
    agoraToken = data.string("agora_token") ?? ""
  }

  var body: some View {
    VideoCallLayout(call: call, swapped: $swapped, whiteBody: true, onBack: showExitDialog)
      .task { await start() }
      .onAppear { CallCoordinator.shared.activeCall = (sessionId, { forceClose($0) }, { Task { await endSession() } }) }
      .onDisappear {
        if CallCoordinator.shared.activeCall?.0 == sessionId { CallCoordinator.shared.activeCall = nil }
        release()
      }
  }

  private func start() async {
    // Hung up on the system screen before this screen came up.
    if CallCoordinator.shared.takeHungUp(sessionId) {
      await endSession()
      return
    }
    socket = CallSocket(sessionId: sessionId, role: "counsellor") { handle($0) }
    guard await AgoraCall.requestPermissions() else {
      app.show("Camera & microphone permissions are needed for the call.")
      await endSession()
      return
    }
    // Over while the permission prompt was up: no camera for a finished call.
    guard !sessionEnded, !finished else { return }
    call.onRemoteLeft = { forceClose("Session ended by the other participant.", endOnServer: true) }
    if !call.join(token: agoraToken, channel: channelName, uid: uid) {
      app.show("Couldn't start the video call")
      // Already accepted on the server.
      await endSession()
    }
  }

  private func handle(_ message: JSONObject) {
    switch message["type"] as? String {
    case "BALANCE_UPDATE":
      if let balance = Double(message.string("balance") ?? "0"), balance <= 0 {
        forceClose("Call ended: caller's balance exhausted.")
      }
    case "CALL_CANCELLED", "CALL_REJECTED", "CALL_MISSED", "CALL_BALANCE_EXHAUSTED", "CALL_ENDED":
      forceClose(message["body"] as? String ?? "Session ended.")
    default:
      break
    }
  }

  private func showExitDialog() {
    guard !sessionEnded, !forceClosing else { return }
    Task {
      if await NativeAlert.show(
        title: "End Call?", message: "Are you sure you want to end this call?", negative: "Stay", positive: "End",
        destructive: true)
      {
        await endSession()
      }
    }
  }

  private func endSession() async {
    guard !sessionEnded else { return }
    sessionEnded = true
    if !sessionId.isEmpty {
      // Closes either way, as natively.
      _ = try? await app.api.request("POST", "college/counsellor/call/\(sessionId)/end/", body: [:])
    }
    leaveAndFinish()
  }

  /// The call is over from the other side (or CallKit): say so, then close.
  private func forceClose(_ message: String, endOnServer: Bool = false) {
    guard !forceClosing, !sessionEnded, !finished else { return }
    forceClosing = true
    sessionEnded = true  // the back button no longer calls the end API
    // Camera, microphone and the system call stop now, not on OK.
    release()
    ConsultationCalls.shared.endedInApp(sessionId: sessionId)
    if endOnServer, !sessionId.isEmpty {
      // The student may have dropped without ending it: don't leave it open.
      Task { _ = try? await app.api.request("POST", "college/counsellor/call/\(sessionId)/end/", body: [:]) }
    }
    Task {
      _ = await NativeAlert.show(
        title: "Session Ended", message: message.isEmpty ? "Session ended by a participant." : message,
        positive: "OK")
      leaveAndFinish()
    }
  }

  private func leaveAndFinish() {
    guard !finished else { return }
    finished = true
    release()
    ConsultationCalls.shared.endedInApp(sessionId: sessionId)
    CallPresenter.dismiss(key: sessionId)
  }

  private func release() {
    socket?.close()
    socket = nil
    call.leave()
  }
}

// MARK: - Coordinator (CounsellorCalls)

/// iOS mentor calls: CallKit rings the phone for each VoIP push; with the app
/// open the Android-style IncomingConsultationView shows too. Answering or
/// declining on either one answers or declines both.
@MainActor
final class CallCoordinator {
  static let shared = CallCoordinator()

  /// The ringing screen: accept-from-CallKit and close.
  var ringing: [String: (accept: () -> Void, close: () -> Void)] = [:]
  /// The mentor call on screen: session, force-close, hang up.
  var activeCall: (String, (String) -> Void, () -> Void)?
  /// A call that came in with no foreground scene to present over.
  private var waiting: (sessionId: String, userName: String?, autoAccept: Bool, at: Date)?
  /// Hung up on the system screen while the accept was still on its way.
  private var hungUpSessions: Set<String> = []
  private weak var app: AppState?

  /// Starts listening for CallKit (once logged in); a fresh PushKit token
  /// goes to the server.
  func start(app: AppState) {
    self.app = app
    ConsultationCalls.shared.onVoipToken = { Task { await NotificationSync.syncIfNeeded() } }
    ConsultationCalls.shared.onEvent = { [weak self] event, session, name in
      self?.handle(event, session, name)
    }
  }

  private func handle(_ event: CallKitEvent, _ sessionId: String, _ userName: String?) {
    guard let app else { return }
    let ring = ringing[sessionId]
    let inCall = activeCall?.0 == sessionId
    switch event {
    case .incoming:
      guard ring == nil, !inCall else { return }
      if rejectIfBusy(app, sessionId) { return }
      present(app, sessionId, userName, autoAccept: false)
    case .answered:
      guard !inCall else { return }
      if let ring {
        ring.accept()
      } else if !rejectIfBusy(app, sessionId) {
        present(app, sessionId, userName, autoAccept: true)
      }
    case .declined:
      ring?.close()
      if waiting?.sessionId == sessionId { waiting = nil }
    case .ended:
      ring?.close()
      if waiting?.sessionId == sessionId { waiting = nil }
      if inCall { activeCall?.1("Session ended.") }
    case .hungUp:
      if inCall {
        activeCall?.2()
      } else if waiting?.sessionId == sessionId {
        // Answered, then hung up before the app could accept it on the server.
        waiting = nil
        Task { _ = try? await app.api.request("POST", "college/call/\(sessionId)/reject/", body: [:]) }
      } else {
        hungUpSessions.insert(sessionId)
      }
    }
  }

  /// Answers and forgets a hang-up that came before the call screen was up.
  func takeHungUp(_ sessionId: String) -> Bool {
    hungUpSessions.remove(sessionId) != nil
  }

  /// One call at a time: a second session is turned down while another call
  /// is on screen or waiting to be.
  private func rejectIfBusy(_ app: AppState, _ sessionId: String) -> Bool {
    let waitingOther = waiting.map { $0.sessionId != sessionId } ?? false
    guard waitingOther || CallPresenter.isBusy(except: sessionId) else { return false }
    ConsultationCalls.shared.endedInApp(sessionId: sessionId)
    Task { _ = try? await app.api.request("POST", "college/call/\(sessionId)/reject/", body: [:]) }
    return true
  }

  private func present(_ app: AppState, _ sessionId: String, _ userName: String?, autoAccept: Bool) {
    // In the background or on the lock screen there is nothing to present
    // over: HomeShellView calls showWaiting once the app is active.
    guard Platform.topViewController() != nil else {
      waiting = (sessionId, userName, autoAccept, Date())
      if autoAccept {
        // A ringing call times out on its own; an answered one has to here.
        Task { [weak self] in
          try? await Task.sleep(seconds: Double(ringSeconds))
          self?.expireWaiting()
        }
      }
      return
    }
    CallPresenter.present(
      IncomingConsultationView(sessionId: sessionId, userName: userName, autoAccept: autoAccept), key: sessionId, app: app)
  }

  /// Answered on the system screen and not opened in time: the student's wait
  /// is over, so it is dropped rather than accepted late.
  private func expireWaiting() {
    guard let call = waiting, call.autoAccept, Date().timeIntervalSince(call.at) >= Double(ringSeconds) else { return }
    waiting = nil
    ConsultationCalls.shared.abandonAnswered(sessionId: call.sessionId)
  }

  /// Shows the call that came in while the app wasn't in the foreground.
  func showWaiting() {
    CallPresenter.presentPending()
    expireWaiting()
    guard let app, let call = waiting else { return }
    waiting = nil
    present(app, call.sessionId, call.userName, autoAccept: call.autoAccept)
  }
}

// MARK: - Incoming consultation (IncomingCounsellorConsultationActivity)

// The WhatsApp/FaceTime-style green incoming-call palette, on the CollegeBook
// brand green (AppColors.primary 0x004D40).
private let callTop = Color(hex: 0x14715D)
private let callBottom = Color(hex: 0x072A22)
private let callAvatarFill = Color(hex: 0x5E8E82)
private let declineRed = Color(hex: 0xE8453C)
private let acceptGreen = Color(hex: 0x22C55E)
private let ringSeconds = 30

/// Rings for 30s, then declines. Accept → college/call/{id}/accept/ → the
/// video call.
struct IncomingConsultationView: View {
  let sessionId: String
  let userName: String?
  /// Already answered on the system call screen: accept straight away.
  let autoAccept: Bool

  @EnvironmentObject private var app: AppState
  @State private var secondsLeft = ringSeconds
  @State private var responding = false
  @State private var closed = false
  @State private var countdown: Task<Void, Never>?
  @State private var pulse = false

  /// The avatar initial: the caller's first letter, "S" (Student) by default.
  private var initial: String {
    let name = (userName ?? "").trimmingCharacters(in: .whitespaces)
    return String(name.first ?? "S").uppercased()
  }

  var body: some View {
    let name = userName?.trimmingCharacters(in: .whitespaces) ?? ""
    let displayName = name.isEmpty ? "Student" : name
    // The avatar gives way on small phones so the buttons stay on screen.
    let avatarScale = min(1, max(0.45, (UIScreen.main.bounds.height - 440) / 300))
    return ZStack {
      LinearGradient(colors: [callTop, callBottom], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        Text("Video consultation").font(.inter(17, .semibold)).foregroundStyle(.white)
          .padding(.horizontal, 22).padding(.vertical, 12)
          .background(.white.opacity(0.14), in: Capsule())
          .padding(.top, 8)

        Spacer()

        // Pulsing avatar with the caller's initial.
        ZStack {
          Circle().fill(.white.opacity(0.06)).frame(width: 300, height: 300)
            .scaleEffect(pulse ? 1.04 : 0.88).opacity(pulse ? 0 : 0.8)
          Circle().fill(.white.opacity(0.08)).frame(width: 232, height: 232)
          Circle().fill(callAvatarFill).frame(width: 170, height: 170)
            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 2))
          Text(initial).font(.inter(78, .bold)).foregroundStyle(.white)
        }
        .frame(width: 300, height: 300)
        .scaleEffect(avatarScale)
        .frame(width: 300 * avatarScale, height: 300 * avatarScale)
        .onAppear {
          withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }

        Text(displayName).font(.inter(32, .bold)).foregroundStyle(.white)
          .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
          .padding(.horizontal, 24).padding(.top, 28)
        Text("Incoming video call").font(.inter(19)).foregroundStyle(.white.opacity(0.72))
          .padding(.top, 10)

        // Auto-decline countdown as a draining bar.
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.22))
            Capsule().fill(.white)
              .frame(width: geo.size.width * CGFloat(secondsLeft) / CGFloat(ringSeconds))
              .animation(.linear(duration: 1), value: secondsLeft)
          }
        }
        .frame(width: 230, height: 4).padding(.top, 36)
        Text("Auto-declines in \(secondsLeft)s").font(.inter(14))
          .foregroundStyle(.white.opacity(0.6)).padding(.top, 14)

        Spacer()

        // Decline / Accept.
        HStack(alignment: .top, spacing: 0) {
          callButton("phone.down.fill", declineRed, "Decline") { respond(accept: false) }
          Spacer()
          callButton("video.fill", acceptGreen, "Accept") { respond(accept: true) }
        }
        .padding(.horizontal, 52).padding(.bottom, 24)
      }

      if responding {
        Color.black.opacity(0.25).ignoresSafeArea()
        ProgressView().tint(.white).controlSize(.large)
      }
    }
    .onAppear {
      CallCoordinator.shared.ringing[sessionId] = (
        accept: { respond(accept: true, fromCallKit: true) }, close: { close() }
      )
      if autoAccept { respond(accept: true, fromCallKit: true) } else { startCountdown() }
    }
    .onDisappear {
      CallCoordinator.shared.ringing.removeValue(forKey: sessionId)
      countdown?.cancel()
    }
  }

  /// A round call-action button (icon in a filled circle) with a label below.
  private func callButton(
    _ icon: String, _ color: Color, _ label: String, action: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 14) {
      Button(action: action) {
        ZStack {
          Circle().fill(color).frame(width: 74, height: 74)
          Image(systemName: icon).font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
        }
      }
      .buttonStyle(.plain)
      Text(label).font(.inter(16, .medium)).foregroundStyle(.white)
    }
    .disabled(responding)
    .opacity(responding ? 0.6 : 1)
  }

  private func startCountdown() {
    countdown?.cancel()
    secondsLeft = ringSeconds
    countdown = Task {
      while !Task.isCancelled {
        try? await Task.sleep(seconds: 1)
        if Task.isCancelled { return }
        if secondsLeft <= 1 {
          respond(accept: false)
          return
        }
        secondsLeft -= 1
      }
    }
  }

  /// Declined or over elsewhere (system call screen, student cancelled).
  private func close() {
    guard !closed else { return }
    closed = true
    CallPresenter.dismiss(key: sessionId)
  }

  private func respond(accept: Bool, fromCallKit: Bool = false) {
    guard !responding, !closed else { return }
    responding = true
    countdown?.cancel()
    // Already hung up on the system screen: accepting can only decline now.
    let accepting = accept && !CallCoordinator.shared.takeHungUp(sessionId)
    if !fromCallKit {
      // Stop the system call screen ringing; no API call from there.
      if accepting {
        ConsultationCalls.shared.answeredInApp(sessionId: sessionId)
      } else {
        ConsultationCalls.shared.endedInApp(sessionId: sessionId)
      }
    }
    Task {
      let json = try? await app.api.request("POST", "college/call/\(sessionId)/\(accepting ? "accept" : "reject")/", body: [:])
      guard !closed else { return }
      if !accepting { return close() }
      let hungUp = CallCoordinator.shared.takeHungUp(sessionId)
      if let data = json?.object("data") {
        if hungUp {
          // Hung up while the accept was on its way: nobody is on this call.
          _ = try? await app.api.request("POST", "college/counsellor/call/\(sessionId)/end/", body: [:])
          return close()
        }
        closed = true
        CallPresenter.dismiss(key: sessionId) {
          let view = CounsellorVideoCallView(sessionId: sessionId, accept: data)
          CallPresenter.present(view, key: view.sessionId, app: app)
        }
        return
      }
      if hungUp {
        _ = try? await app.api.request("POST", "college/call/\(sessionId)/reject/", body: [:])
        return close()
      }
      // Let them try again while the student is still waiting.
      app.show("Failed to accept. Please try again.")
      responding = false
      startCountdown()
    }
  }
}
