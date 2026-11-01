import AVFoundation
import AgoraRtcKit
import SwiftUI

/// AppConstants.appId of the native app.
private let agoraAppId = "052d071326e84eaa9176e28c6695933b"

/// One Agora video call: the engine, the two video surfaces and the remote
/// user's comings and goings.
@MainActor
final class AgoraCall: NSObject, ObservableObject {
  let localView = UIView()
  let remoteView = UIView()
  @Published var localConnected = false
  @Published var remoteUid: UInt?
  @Published var muted = false

  var onRemoteJoined: ((UInt) -> Void)?
  var onRemoteLeft: (() -> Void)?

  private var engine: AgoraRtcEngineKit?

  override init() {
    localView.backgroundColor = .black
    remoteView.backgroundColor = .black
    super.init()
  }

  /// Camera and microphone, asking if not yet decided.
  static func requestPermissions() async -> Bool {
    let video = await AVCaptureDevice.requestAccess(for: .video)
    let audio = await AVCaptureDevice.requestAccess(for: .audio)
    return video && audio
  }

  /// Starts the engine with camera preview and joins as a broadcaster in a
  /// communication channel, speaker on. False if the engine can't start.
  func join(token: String, channel: String, uid: Int) -> Bool {
    let config = AgoraRtcEngineConfig()
    config.appId = agoraAppId
    config.channelProfile = .communication
    let engine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
    self.engine = engine
    engine.enableVideo()
    engine.enableAudio()
    engine.setDefaultAudioRouteToSpeakerphone(true)
    engine.muteLocalAudioStream(false)
    let canvas = AgoraRtcVideoCanvas()
    canvas.uid = 0
    canvas.view = localView
    canvas.renderMode = .hidden
    engine.setupLocalVideo(canvas)
    engine.startPreview()
    let options = AgoraRtcChannelMediaOptions()
    options.channelProfile = .communication
    options.clientRoleType = .broadcaster
    options.publishCameraTrack = true
    options.publishMicrophoneTrack = true
    options.autoSubscribeAudio = true
    options.autoSubscribeVideo = true
    let result = engine.joinChannel(byToken: token, channelId: channel, uid: UInt(max(uid, 0)), mediaOptions: options)
    if result == 0 { localConnected = true }
    return result == 0
  }

  func switchCamera() { engine?.switchCamera() }

  func toggleMute() {
    muted.toggle()
    engine?.muteLocalAudioStream(muted)
  }

  /// Leaves the channel and releases the engine.
  func leave() {
    // They hold the screen, which holds this call.
    onRemoteJoined = nil
    onRemoteLeft = nil
    guard let engine else { return }
    self.engine = nil
    engine.stopPreview()
    engine.leaveChannel(nil)
    AgoraRtcEngineKit.destroy()
  }
}

extension AgoraCall: AgoraRtcEngineDelegate {
  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
    Task { @MainActor in
      // Queued before leave(): the engine has gone.
      guard self.engine === engine else { return }
      let canvas = AgoraRtcVideoCanvas()
      canvas.uid = uid
      canvas.view = self.remoteView
      canvas.renderMode = .hidden
      engine.setupRemoteVideo(canvas)
      self.remoteUid = uid
      self.onRemoteJoined?(uid)
    }
  }

  nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
    Task { @MainActor in
      guard self.engine === engine else { return }
      self.remoteUid = nil
      self.onRemoteLeft?()
    }
  }
}

/// The call socket (CallSocketManager / CounsellorCallSocketManager):
/// wss://host/ws/call/{session}/{user|counsellor}/?token=…
final class CallSocket: @unchecked Sendable {
  private var task: URLSessionWebSocketTask?
  private let onMessage: @MainActor (JSONObject) -> Void

  init(sessionId: String, role: String, onMessage: @escaping @MainActor (JSONObject) -> Void) {
    self.onMessage = onMessage
    guard !sessionId.isEmpty else { return }
    var parts = URLComponents()
    parts.scheme = "wss"
    parts.host = APIClient.shared.apiHost
    parts.path = "/ws/call/\(sessionId)/\(role)/"
    parts.queryItems = [URLQueryItem(name: "token", value: SessionStore.shared.accessToken ?? "")]
    guard let url = parts.url else { return }
    // Logged without the URL: it carries the token.
    #if DEBUG
      NSLog("CallSocketManager: Connecting call socket (%@)", role)
    #endif
    task = URLSession.shared.webSocketTask(with: url)
    task?.resume()
    receive()
  }

  private func receive() {
    task?.receive { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let message):
        var text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: break
        }
        if let text, let data = text.data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
        {
          #if DEBUG
            NSLog("CallSocketManager: message type=%@", json["type"] as? String ?? "?")
          #endif
          Task { @MainActor in self.onMessage(json) }
        }
        self.receive()
      case .failure(let error):
        // CallSocketManager only logs a failed socket.
        #if DEBUG
          NSLog("CallSocketManager: Socket failure: %@", String(describing: type(of: error)))
        #endif
      }
    }
  }

  func close() {
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
  }
}

// MARK: - Views

/// Hosts an existing UIView (an Agora surface) so it can move between boxes.
struct HostedView: UIViewRepresentable {
  let view: UIView?

  func makeUIView(context: Context) -> UIView {
    let container = UIView()
    container.backgroundColor = .black
    container.clipsToBounds = true
    return container
  }

  func updateUIView(_ container: UIView, context: Context) {
    guard let view else {
      container.subviews.forEach { $0.removeFromSuperview() }
      return
    }
    guard view.superview !== container else { return }
    container.subviews.forEach { $0.removeFromSuperview() }
    view.removeFromSuperview()
    view.frame = container.bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(view)
  }
}

/// activity_agora_video_call.xml: the green header, two outlined video boxes
/// (tap to swap) and the switch / mute / end buttons.
struct VideoCallLayout: View {
  @ObservedObject var call: AgoraCall
  @Binding var swapped: Bool
  var badge: String? = nil
  var whiteBody = false
  let onBack: () -> Void

  var body: some View {
    let remote: UIView? = call.remoteUid == nil ? nil : call.remoteView
    let local: UIView? = call.localConnected ? call.localView : nil
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button(action: onBack) {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(.white)
        }
        .accessibilityLabel("Back")
        Text("Video Call").font(.inter(16, .bold)).foregroundStyle(.white)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 16)
      .background(AppColors.primary)

      ZStack(alignment: .topLeading) {
        VStack(spacing: 12) {
          videoBox(swapped ? local : remote)
          videoBox(swapped ? remote : local)
        }
        .padding(10)
        if let badge {
          Text(badge).font(.inter(14, .medium)).foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(.white, in: Capsule())
            .padding(30)
        }
      }

      HStack(spacing: 16) {
        PressedImageButton(label: "Switch camera", name: "call_btn_switch_camera") { call.switchCamera() }
        PressedImageButton(label: call.muted ? "Unmute" : "Mute", name: call.muted ? "call_btn_mute" : "call_btn_unmute") {
          call.toggleMute()
        }
        PressedImageButton(label: "End call", name: "call_btn_endcall", action: onBack)
      }
      .padding(.bottom, 24)
    }
    .background(whiteBody ? Color.white : Color.black)
    .background(Color.black.ignoresSafeArea())
  }

  /// A black 16pt card with the 2pt #8BC34A outline.
  private func videoBox(_ view: UIView?) -> some View {
    HostedView(view: view)
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x8BC34A), lineWidth: 2))
      .contentShape(Rectangle())
      .onTapGesture {
        // Tapping either box swaps the two videos once the other side is in.
        if call.remoteUid != nil { swapped.toggle() }
      }
  }
}

/// The btn_* state-list drawables: the _pressed bitmap while held.
struct PressedImageButton: View {
  let label: String
  let name: String
  let action: () -> Void

  var body: some View {
    Button(action: action) { EmptyView() }
      .buttonStyle(PressedImageStyle(name: name))
      .accessibilityLabel(label)
  }

  private struct PressedImageStyle: ButtonStyle {
    let name: String
    func makeBody(configuration: Configuration) -> some View {
      Image("\(name)_\(configuration.isPressed ? "pressed" : "normal")").resizable().scaledToFill()
        .frame(width: 70, height: 70)
    }
  }
}
