import Combine
import PhotosUI
import SafariServices
import SwiftUI
import UniformTypeIdentifiers

private let chatBg = Color(hex: 0xF2EDE4)
private let chatMeta = Color(hex: 0x6B7280)
private let historyLimit = 30
private let loadMoreThreshold = 5
private let maxMessageLength = 1000
private let maxFileBytes = 10 * 1024 * 1024

/// Group slugs from chat/groups/ — they don't change while the app runs.
@MainActor
private enum Groups {
  static var nationalSlug: String?
  static var stateSlugByName: [String: String] = [:]
  static var loaded = false

  static func slugFor(allIndia: Bool, state: String?) -> String {
    guard !allIndia, let state else { return nationalSlug ?? "all-india" }
    let key = state.trimmingCharacters(in: .whitespaces).lowercased()
    if let slug = stateSlugByName[key] { return slug }
    return key.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }
}

/// Community → Chats: the group room of the All India / state selection
/// (GroupChatFragment).
@MainActor
final class GroupChatModel: ObservableObject {
  /// Oldest first, with date headers.
  @Published var list: [ChatBubble] = []
  @Published var status: String? = "Connecting…"
  @Published var sending = false
  @Published var replyTo: ChatBubble?
  /// Bumped to ask the view to scroll to the newest message.
  @Published var scrollToBottomRequest = 0
  /// Set to keep a row in place after older history lands above it.
  @Published var anchorAfterPrepend: String?
  @Published var scrollTarget: String?

  @Published private(set) var roomId: String?
  @Published private var allIndia = true
  @Published private var stateName = ""
  @Published private var roomUnavailable = false
  @Published private var groupsLoading = false
  @Published private var hasMoreHistory = false
  @Published private(set) var loadingMoreHistory = false
  @Published private var catchingUp = false
  /// Asked for while one was running: another follows it.
  private var catchUpQueued = false
  /// The latest page has landed. The list alone can't say: a socket message
  /// or the user's own send can arrive first.
  private var historyLoaded = false
  /// The last id known to have nothing missing before it while the socket is
  /// down. A send lands past messages not fetched yet, so the newest id won't do.
  private var gapStart: Int?
  /// Set by the view once the first scroll to the newest message has run;
  /// before that, top rows appearing isn't the reader scrolling up.
  var historyArmed = false
  private let parser = ChatParser()
  private var socket: URLSessionWebSocketTask?
  private var socketReady = false
  private var socketGeneration = 0
  private var routeWatch: AnyCancellable?
  private var reconnectTask: Task<Void, Never>?
  private var reconnectAttempt = 0
  /// Set by the view when it appears (it comes from the environment).
  var app: AppState!

  deinit {
    reconnectTask?.cancel()
    socket?.cancel(with: .goingAway, reason: nil)
  }

  /// Logged out or expired: the socket closes with the session.
  func watchSession() {
    routeWatch = app.$route.sink { [weak self] route in
      guard let self, route != .home else { return }
      MainActor.assumeIsolated { self.shutdown() }
    }
  }

  private func shutdown() {
    reconnectTask?.cancel()
    closeSocket()
    roomId = nil
  }

  // MARK: Rooms

  func setRoom(allIndia: Bool, state: String) {
    self.allIndia = allIndia
    stateName = state
    if !Groups.loaded {
      Task { await loadGroupsThenOpen() }
      return
    }
    openRoom(Groups.slugFor(allIndia: allIndia, state: state))
  }

  private func loadGroupsThenOpen() async {
    guard !groupsLoading else { return }
    groupsLoading = true
    status = "Connecting…"
    if let json = try? await app.api.get("chat/groups/") {
      Groups.stateSlugByName.removeAll()
      for g in (json.object("data") ?? [:]).objects("results") {
        guard let slug = g.string("slug") else { continue }
        if (g.string("group_type") ?? "").uppercased() == "NATIONAL" {
          if Groups.nationalSlug == nil { Groups.nationalSlug = slug }
          continue
        }
        let name = (g.string("name") ?? "")
          .replacingOccurrences(of: #"\s*counselling\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
          .trimmingCharacters(in: .whitespaces).lowercased()
        Groups.stateSlugByName[name] = slug
      }
      Groups.loaded = true
    }
    // Falls back to the state name in slug form.
    groupsLoading = false
    openRoom(Groups.slugFor(allIndia: allIndia, state: stateName))
  }

  private func openRoom(_ slug: String) {
    if slug == roomId, socket != nil || !list.isEmpty || roomUnavailable { return }
    roomId = slug
    resetRoom()
    if Groups.loaded, !Groups.stateSlugByName.isEmpty, !allIndia,
      !Groups.stateSlugByName.values.contains(slug)
    {
      return markUnavailable()
    }
    connect()
  }

  private func markUnavailable() {
    roomUnavailable = true
    reconnectTask?.cancel()
    closeSocket()
    status = allIndia ? "This chat group isn't available." : "There's no chat group for \(stateName) yet."
  }

  private func resetRoom() {
    reconnectTask?.cancel()
    reconnectAttempt = 0
    closeSocket()
    list = []
    hasMoreHistory = false
    loadingMoreHistory = false
    catchingUp = false
    catchUpQueued = false
    historyLoaded = false
    historyArmed = false
    gapStart = nil
    roomUnavailable = false
    parser.removedIds.removeAll()
    replyTo = nil
    status = "Connecting…"
  }

  /// Back from the background: fetch what was missed, reconnect if dropped.
  func resumed() {
    guard roomId != nil, !roomUnavailable else { return }
    if socket == nil {
      reconnectTask?.cancel()
      reconnectAttempt = 0
      connect()
    } else {
      catchUp()
      probeSocket()
    }
  }

  // MARK: Socket

  /// A connection that died in the background may not have reported it yet.
  private func probeSocket() {
    let generation = socketGeneration
    socket?.sendPing { [weak self] error in
      guard error != nil else { return }
      Task { @MainActor in self?.onSocketLost(generation) }
    }
  }

  private func closeSocket() {
    socketGeneration += 1
    socketReady = false
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
  }

  private func connect() {
    guard let room = roomId else { return }
    guard let token = app.session.accessToken, !token.isEmpty else {
      status = "Log in to join the chat."
      return
    }
    if list.isEmpty { status = "Connecting…" }
    var parts = URLComponents()
    parts.scheme = "wss"
    parts.host = app.api.apiHost
    parts.path = "/ws/chat/\(room)/"
    parts.queryItems = [URLQueryItem(name: "token", value: token)]
    guard let url = parts.url else { return }
    socketGeneration += 1
    let generation = socketGeneration
    let task = URLSession.shared.webSocketTask(with: url)
    socket = task
    task.resume()
    // The first message (or a ping) proves the socket is open.
    task.sendPing { [weak self] error in
      Task { @MainActor in
        guard let self, generation == self.socketGeneration else { return }
        if error != nil { return self.onSocketLost(generation) }
        self.socketReady = true
        self.reconnectAttempt = 0
        if self.historyLoaded { self.catchUp() } else { await self.loadLatest() }
      }
    }
    receive(task, generation)
  }

  private func receive(_ task: URLSessionWebSocketTask, _ generation: Int) {
    task.receive { [weak self] result in
      Task { @MainActor in
        guard let self, generation == self.socketGeneration else { return }
        switch result {
        case .success(let message):
          var text: String?
          if case .string(let s) = message { text = s }
          if case .data(let d) = message { text = String(data: d, encoding: .utf8) }
          if let text, let data = text.data(using: .utf8),
            let event = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
          {
            self.handle(event)
          }
          self.receive(task, generation)
        case .failure:
          self.onSocketLost(generation)
        }
      }
    }
  }

  /// History still loads over REST; the socket retries 2s, 4s … 30s.
  private func onSocketLost(_ generation: Int) {
    // A failed handshake reports through both the ping and the receive.
    guard generation == socketGeneration, socket != nil else { return }
    socket = nil
    socketReady = false
    guard !roomUnavailable else { return }
    if gapStart == nil, newestId > 0 { gapStart = newestId }
    if historyLoaded { catchUp() } else { Task { await loadLatest() } }
    let delay = min(30, 2 << min(reconnectAttempt, 4))
    reconnectAttempt += 1
    reconnectTask?.cancel()
    reconnectTask = Task {
      try? await Task.sleep(seconds: Double(delay))
      guard !Task.isCancelled, socket == nil, roomId != nil, !roomUnavailable else { return }
      connect()
    }
  }

  private func handle(_ event: JSONObject) {
    let type = event.string("type") ?? event.string("event") ?? ""
    let payload = eventPayload(event)
    switch type {
    case "message_created":
      let message = messageObject(payload)
      guard (message.int("id") ?? 0) > 0 else { return }
      let incoming = parser.parse(message)
      merge(incoming)
      if atBottom || incoming[0].mine { scrollToBottomRequest += 1 }
    case "message_hidden":
      removeMessage(messageIdOf(payload))
    case "message_restored":
      let message = messageObject(payload)
      if message["created_at"] != nil {
        let bubbles = parser.parse(message)
        replaceMessage(bubbles[0].id, bubbles)
      } else {
        Task { await refetchMessage(messageIdOf(payload)) }
      }
    case "attachment_hidden", "attachment_restored":
      Task { await refetchMessage(messageIdOf(payload)) }
    default:
      break
    }
  }

  // MARK: History

  private func fetchPage(before: Int? = nil, after: Int? = nil, onError: ((APIError) -> Void)? = nil) async -> (
    data: JSONObject, batch: [ChatBubble]
  )? {
    guard let slug = roomId else { return nil }
    var query = ["limit": "\(historyLimit)"]
    if let before { query["before"] = "\(before)" }
    if let after { query["after"] = "\(after)" }
    do {
      let json = try await app.api.get("chat/groups/\(slug)/messages/", query: query)
      guard slug == roomId else { return nil }
      let data = json.object("data") ?? [:]
      var batch: [ChatBubble] = []
      for m in data.objects("results") where (m.int("id") ?? 0) > 0 { batch += parser.parse(m) }
      return (data, Self.sortedById(batch))
    } catch {
      guard slug == roomId else { return nil }
      onError?(error as? APIError ?? APIError.offline)
      return nil
    }
  }

  private func loadLatest() async {
    let page = await fetchPage { [weak self] error in
      guard let self, self.list.isEmpty else { return }
      switch error.payload?.string("message") {
      case "GROUP_NOT_FOUND": self.markUnavailable()
      case "PROFILE_INACTIVE": self.status = "Your profile is deactivated."
      default: self.status = "Couldn't connect to the chat right now."
      }
    }
    guard let page else { return }
    hasMoreHistory = page.data.bool("has_more") == true
    historyLoaded = true
    historyArmed = false
    gapStart = socketReady ? nil : page.batch.last?.id
    merge(page.batch)
    scrollToBottomRequest += 1
    status = list.isEmpty ? "No messages yet. Say hi 👋" : nil
  }

  private func catchUp() {
    guard !catchingUp else {
      catchUpQueued = true
      return
    }
    let from = gapStart ?? newestId
    guard historyLoaded, from > 0 else {
      Task { await loadLatest() }
      return
    }
    catchingUp = true
    let socketWasOpen = socketReady
    Task { await fetchNewer(after: from, socketWasOpen: socketWasOpen) }
  }

  private func fetchNewer(after: Int, socketWasOpen: Bool) async {
    guard let page = await fetchPage(after: after, onError: { _ in }) else {
      finishCatchUp()
      return
    }
    let wasAtBottom = atBottom
    merge(page.batch)
    if wasAtBottom, !page.batch.isEmpty { scrollToBottomRequest += 1 }
    status = list.isEmpty ? "No messages yet. Say hi 👋" : nil
    let newest = max(page.data.int("newest_id") ?? 0, page.batch.last?.id ?? 0)
    if page.data.bool("has_more") == true, !page.batch.isEmpty, newest > after {
      await fetchNewer(after: newest, socketWasOpen: socketWasOpen)
    } else {
      // With no socket yet, anything sent after this page is still to fetch.
      gapStart = socketWasOpen ? nil : max(newest, after)
      finishCatchUp()
    }
  }

  private func finishCatchUp() {
    catchingUp = false
    if catchUpQueued {
      catchUpQueued = false
      catchUp()
    }
  }

  @discardableResult
  func loadMoreHistory(anchor: (() -> String?)? = nil) async -> Bool {
    let oldest = oldestId
    guard hasMoreHistory, !loadingMoreHistory, oldest > 0 else { return false }
    loadingMoreHistory = true
    let page = await fetchPage(before: oldest, onError: { _ in })
    loadingMoreHistory = false
    guard let page else { return false }
    hasMoreHistory = page.data.bool("has_more") == true
    let older = page.batch.filter { $0.id < oldest }
    if older.isEmpty { return true }
    // Keep what's on screen still while older rows land above.
    anchorAfterPrepend = anchor?() ?? list.first { $0.type != .header }?.rowId
    rebuild(older + messages)
    return true
  }

  private func refetchMessage(_ id: Int) async {
    guard id > 0, let page = await fetchPage(before: id + 1) else { return }
    let bubbles = page.batch.filter { $0.id == id }
    if bubbles.isEmpty { removeMessage(id) } else { replaceMessage(id, bubbles) }
  }

  // MARK: List edits

  private var messages: [ChatBubble] { list.filter { $0.type != .header } }
  private var newestId: Int { list.last { $0.id > 0 }?.id ?? 0 }
  private var oldestId: Int { list.first { $0.id > 0 }?.id ?? 0 }
  @Published var atBottom = true

  /// Stable, so a message's attachments keep their order.
  private static func sortedById(_ list: [ChatBubble]) -> [ChatBubble] {
    list.enumerated().sorted { a, b in a.element.id != b.element.id ? a.element.id < b.element.id : a.offset < b.offset }
      .map(\.element)
  }

  private func merge(_ incoming: [ChatBubble]) {
    guard !incoming.isEmpty else { return }
    let shown = Set(list.map(\.rowId))
    let fresh = incoming.filter { !shown.contains($0.rowId) }
    guard !fresh.isEmpty else { return }
    rebuild(messages + fresh)
    status = nil
  }

  private func rebuild(_ messages: [ChatBubble]) {
    var out: [ChatBubble] = []
    var lastKey: String?
    for m in Self.sortedById(messages) {
      let key = dayKeyOf(m)
      if key != lastKey {
        out.append(ChatBubble(header: dateLabelFor(m.at)))
        lastKey = key
      }
      out.append(m)
    }
    list = out
  }

  private func removeMessage(_ id: Int) {
    guard id > 0 else { return }
    let remaining = messages.filter { $0.id != id }
    if remaining.count != messages.count { rebuild(remaining) }
    updateRepliesQuoting("\(id)", nil)
    if list.isEmpty { status = "No messages yet. Say hi 👋" }
  }

  private func replaceMessage(_ id: Int, _ bubbles: [ChatBubble]) {
    // Older than what's loaded: paging will bring it. Listed now, it would
    // become the oldest id and the history before it would be skipped.
    if id >= oldestId || !hasMoreHistory { rebuild(messages.filter { $0.id != id } + bubbles) }
    updateRepliesQuoting("\(id)", ChatParser.quoteOf(bubbles))
    status = nil
  }

  private func updateRepliesQuoting(_ target: String, _ quote: ReplyQuote?) {
    for m in list {
      guard let r = m.reply, r.targetId == target else { continue }
      m.reply = quote ?? ReplyQuote(preview: removedText, name: r.name, targetId: target)
    }
    if quote == nil { parser.removedIds.insert(target) } else { parser.removedIds.remove(target) }
    list = list
  }

  /// Jumps to a quoted message, paging older history until it turns up.
  func navigateTo(_ target: String?) async {
    guard let target, !parser.removedIds.contains(target) else { return }
    while !list.contains(where: { $0.serverId == target }) {
      if loadingMoreHistory { return }
      if !hasMoreHistory { return app.show("Original message not found") }
      if await !loadMoreHistory() { return }
    }
    scrollTarget = list.first { $0.serverId == target }?.rowId
  }

  // MARK: Sending

  func send(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      app.show("Message cannot be empty")
      return false
    }
    guard trimmed.count <= maxMessageLength else {
      app.show("Message is too long (\(trimmed.count)/\(maxMessageLength) characters)")
      return false
    }
    Task { await post(trimmed, file: nil) }
    return true
  }

  var onSent: ((String) -> Void)?

  /// POST chat/groups/{slug}/messages/: text, a file, or both, with reply_to.
  func post(_ text: String?, file: APIClient.UploadFile?) async {
    guard let slug = roomId else { return }
    if roomUnavailable { return app.show("This chat group isn't available") }
    if sending { return app.show("Still sending your last message…") }
    sending = true
    let reply = replyTo
    var fields: [String: String] = [:]
    if let text, !text.isEmpty { fields["message"] = text }
    if let reply { fields["reply_to"] = reply.serverId }
    do {
      let result = try await app.api.postMultipart("chat/groups/\(slug)/messages/", fields: fields, file: file)
      sending = false
      guard (200..<300).contains(result.status), let json = result.json else {
        if result.json?.string("message") == "INVALID_REPLY" { replyTo = nil }
        return app.show(sendErrorText(result.status, result.json))
      }
      onSent?(text ?? "")
      replyTo = nil
      guard slug == roomId else { return }
      let created = messageObject(eventPayload(json))
      if (created.int("id") ?? 0) > 0 {
        merge(parser.parse(created))
        scrollToBottomRequest += 1
      }
    } catch {
      sending = false
      app.show("Couldn't send. Check your connection and try again.")
    }
  }

  /// Only JPG / PNG / PDF up to 10 MB: other photo formats become JPG, a
  /// sideways photo is turned upright, a big one is scaled down.
  func upload(data: Data, name: String, pdf: Bool, caption: String) async {
    guard caption.count <= maxMessageLength else {
      return app.show("Message is too long (\(caption.count)/\(maxMessageLength) characters)")
    }
    var payload = data
    var fileName = name
    var mime = pdf ? "application/pdf" : guessMimeType(name)
    if pdf {
      if !fileName.lowercased().hasSuffix(".pdf") { fileName += ".pdf" }
    } else {
      guard let prepared = Self.prepareImage(data, mime: mime) else {
        return app.show("This photo can't be sent. Choose a JPG or PNG")
      }
      payload = prepared.data
      if prepared.reencoded {
        mime = "image/jpeg"
        fileName = (fileName as NSString).deletingPathExtension + ".jpg"
      }
    }
    guard payload.count <= maxFileBytes else {
      return app.show(pdf ? "PDF must be 10 MB or smaller" : "Photo must be 10 MB or smaller")
    }
    app.show(pdf ? "Sending PDF…" : "Sending photo…")
    await post(caption, file: APIClient.UploadFile(field: "files", data: payload, fileName: fileName, mimeType: mime))
  }

  /// Upright, JPG/PNG and ≤10 MB.
  private static func prepareImage(_ data: Data, mime: String) -> (data: Data, reencoded: Bool)? {
    let jpegOrPng = mime == "image/jpeg" || mime == "image/png"
    guard let image = UIImage(data: data) else { return jpegOrPng ? (data, false) : nil }
    var out = data
    var reencoded = false
    if !jpegOrPng || image.imageOrientation != .up {
      // Drawing bakes the EXIF orientation into the pixels.
      out = image.normalized().jpegData(compressionQuality: 0.9) ?? data
      reencoded = true
    }
    var scale: CGFloat = 0.5
    while out.count > maxFileBytes, scale >= 0.125 {
      let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      out = UIImage.pixelRenderer(size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        .jpegData(compressionQuality: 0.9) ?? out
      reencoded = true
      scale /= 2
    }
    return (out, reencoded)
  }
}

extension UIImage {
  func normalized() -> UIImage {
    guard imageOrientation != .up else { return self }
    return Self.pixelRenderer(size).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
  }

  /// One pixel per point: the default format multiplies by the screen's scale,
  /// which made a 12 MP photo a 110 MP bitmap.
  static func pixelRenderer(_ size: CGSize) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format)
  }
}

// MARK: - View

struct GroupChatView: View {
  let allIndia: Bool
  let state: String
  /// False while Q&A is on top of this view.
  let active: Bool

  @EnvironmentObject private var app: AppState
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = GroupChatModel()
  @State private var input = ""
  @State private var attachmentsOpen = false
  @State private var visible = Set<String>()
  @State private var wentToBackground = false
  @State private var stickyLabel: String?
  @State private var stickyTask: Task<Void, Never>?
  @State private var pickingPhoto = false
  @State private var takingPhoto = false
  @State private var pickingPDF = false
  @State private var viewing: URL?
  @FocusState private var inputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      messages(model)
      composer(model)
    }
    .background(chatBg)
    .onAppear {
      if model.app == nil {
        model.app = app
        // Through the binding: a closure over the view would hold its
        // StateObject, so the model (and its socket) could never be freed.
        let draft = $input
        model.onSent = { sent in
          // Anything typed while this was sending stays.
          let spaces = CharacterSet.whitespacesAndNewlines
          if draft.wrappedValue.trimmingCharacters(in: spaces) == sent.trimmingCharacters(in: spaces) {
            draft.wrappedValue = ""
          }
        }
        model.watchSession()
      }
      model.setRoom(allIndia: allIndia, state: state)
    }
    .onChangeCompat(of: allIndia) { _, _ in model.setRoom(allIndia: allIndia, state: state) }
    .onChangeCompat(of: state) { _, _ in model.setRoom(allIndia: allIndia, state: state) }
    .onChangeCompat(of: scenePhase) { _, phase in
      // The way back passes through .inactive, so the old phase can't tell.
      if phase == .background {
        wentToBackground = true
      } else if phase == .active, wentToBackground {
        wentToBackground = false
        model.resumed()
      }
    }
    .onChangeCompat(of: active) { _, active in
      // onLeftChat(): Q&A took over.
      if !active {
        inputFocused = false
        attachmentsOpen = false
      }
    }
    .onChangeCompat(of: inputFocused) { _, focused in if focused { attachmentsOpen = false } }
    .compatPhotoPicker(isPresented: $pickingPhoto) { data, ext in
      Task {
        await model.upload(data: data, name: "photo.\(ext)", pdf: false, caption: input.trimmingCharacters(in: .whitespaces))
      }
    }
    .fullScreenCover(isPresented: $takingPhoto) {
      CameraPicker { image in
        guard let data = image.normalized().jpegData(compressionQuality: 0.92) else { return }
        Task { await model.upload(data: data, name: "camera.jpg", pdf: false, caption: input.trimmingCharacters(in: .whitespaces)) }
      }
      .ignoresSafeArea()
    }
    .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { result in
      guard case .success(let url) = result else { return }
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      guard let data = try? Data(contentsOf: url) else { return }
      guard data.count <= maxFileBytes else { return app.show("PDF must be 10 MB or smaller") }
      Task { await model.upload(data: data, name: url.lastPathComponent, pdf: true, caption: input.trimmingCharacters(in: .whitespaces)) }
    }
    .sheet(item: $viewing) { SafariView(url: $0).ignoresSafeArea() }
  }

  private func messages(_ model: GroupChatModel) -> some View {
    GeometryReader { geo in
      let maxBubble = geo.size.width * 0.74
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(model.list.enumerated()), id: \.element.rowId) { index, m in
              row(model, index: index, maxBubble: maxBubble)
                .id(m.rowId)
                .onAppear {
                  visible.insert(m.rowId)
                  if index == model.list.count - 1 { model.atBottom = true }
                  // Near the oldest loaded message: fetch the page before it.
                  if index <= loadMoreThreshold { loadOlder(model) }
                  updateSticky(model)
                }
                .onDisappear {
                  visible.remove(m.rowId)
                  if index == model.list.count - 1 { model.atBottom = false }
                  updateSticky(model)
                }
            }
          }
          .padding(.horizontal, 2)
          .padding(.vertical, 8)
        }
        .defaultScrollAnchorBottom()
        .dismissesKeyboardInteractively()
        .onTapGesture {
          inputFocused = false
          attachmentsOpen = false
        }
        .onChangeCompat(of: model.scrollToBottomRequest) { _, _ in
          if let last = model.list.last?.rowId {
            DispatchQueue.main.async {
              proxy.scrollTo(last, anchor: .bottom)
              guard !model.historyArmed else { return }
              model.historyArmed = true
              // A short page stays on screen, so its top rows won't appear again.
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if model.list.prefix(loadMoreThreshold + 1).contains(where: { visible.contains($0.rowId) }) {
                  loadOlder(model)
                }
              }
            }
          }
        }
        .onChangeCompat(of: model.anchorAfterPrepend) { _, id in
          guard let id else { return }
          proxy.scrollTo(id, anchor: .top)
          model.anchorAfterPrepend = nil
        }
        .onChangeCompat(of: model.scrollTarget) { _, id in
          guard let id else { return }
          withAnimation { proxy.scrollTo(id, anchor: .center) }
          model.scrollTarget = nil
        }
        .overlay {
          if let status = model.status {
            Text(status).font(.inter(14, .medium)).foregroundStyle(chatMeta).multilineTextAlignment(.center)
              .padding(.horizontal, 32).allowsHitTesting(false)
          }
        }
        .overlay(alignment: .top) {
          if let stickyLabel {
            DateHeaderChip(label: stickyLabel, sticky: true).padding(.top, 8).transition(.opacity).allowsHitTesting(false)
          }
        }
        .animation(.easeInOut(duration: 0.25), value: stickyLabel)
      }
    }
  }

  /// The page before the oldest loaded message, keeping the top row on screen
  /// in place. Before iOS 17 the first layout starts at the top, so this waits
  /// for the first scroll to the newest message.
  private func loadOlder(_ model: GroupChatModel) {
    guard model.historyArmed else { return }
    Task {
      await model.loadMoreHistory(anchor: {
        model.list.first { $0.type != .header && visible.contains($0.rowId) }?.rowId
      })
    }
  }

  /// The sticky date pill for the day at the top; fades after 1.5s.
  private func updateSticky(_ model: GroupChatModel) {
    guard let first = model.list.firstIndex(where: { visible.contains($0.rowId) }) else { return }
    let label = model.list[...first].last { $0.type == .header }?.dateLabel
    guard let label else { return }
    stickyTask?.cancel()
    if stickyLabel != label { stickyLabel = label }
    stickyTask = Task {
      try? await Task.sleep(seconds: 1.5)
      if !Task.isCancelled { stickyLabel = nil }
    }
  }

  @ViewBuilder
  private func row(_ model: GroupChatModel, index: Int, maxBubble: CGFloat) -> some View {
    let m = model.list[index]
    if m.type == .header {
      DateHeaderChip(label: m.dateLabel ?? "").padding(.vertical, 4).frame(maxWidth: .infinity)
    } else {
      let previous = index > 0 ? model.list[index - 1] : nil
      let first = previous == nil || previous!.type == .header || previous!.username != m.username
      let quoteTap: () -> Void = { Task { await model.navigateTo(m.reply?.targetId) } }
      let bubble = Group {
        switch m.type {
        case .image:
          ImageBubbleView(bubble: m, first: first, maxWidth: maxBubble, onQuoteTap: { quoteTap() }) { open(m.url) }
        case .file:
          FileBubbleView(bubble: m, first: first, maxWidth: maxBubble, onQuoteTap: { quoteTap() }) { open(m.url) }
        default:
          TextBubbleView(bubble: m, first: first, maxWidth: maxBubble, onQuoteTap: { quoteTap() })
        }
      }
      SwipeToReply(onReply: { reply(model, m) }) {
        HStack(alignment: .top, spacing: 6) {
          if m.mine {
            Spacer(minLength: 0)
            bubble
          } else {
            ChatAvatar(bubble: m, visible: first)
            bubble
            Spacer(minLength: 0)
          }
        }
        .padding(EdgeInsets(top: 3, leading: 8, bottom: 0, trailing: 8))
      }
      .contextMenu {
        Button("Reply", systemImage: "arrowshape.turn.up.left") { reply(model, m) }
        if let text = m.text, !text.isEmpty {
          Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
      }
    }
  }

  private func reply(_ model: GroupChatModel, _ m: ChatBubble) {
    model.replyTo = m
    inputFocused = true
  }

  private func open(_ url: String?) {
    viewing = url.flatMap { APIClient.shared.mediaURL($0) }
  }

  // MARK: Composer

  private func composer(_ model: GroupChatModel) -> some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 0) {
        VStack(spacing: 0) {
          if let reply = model.replyTo { composerReply(model, reply) }
          HStack(alignment: .bottom, spacing: 0) {
            MultilineTextField($input, prompt: Text("Message").foregroundColor(chatMeta), lines: 1...5)
              .font(.inter(16, .medium))
              .foregroundStyle(.black)
              .focused($inputFocused)
              .padding(.horizontal, 12)
              .padding(.vertical, 9)
              .frame(minHeight: 38)
            Button {
              if attachmentsOpen {
                attachmentsOpen = false
              } else {
                inputFocused = false
                withAnimation(.easeOut(duration: 0.28)) { attachmentsOpen = true }
              }
            } label: {
              Image("ic_baseline_attach_file_24").renderingMode(.template).resizable().frame(width: 26, height: 26)
                .foregroundStyle(.black).padding(EdgeInsets(top: 3, leading: 3, bottom: 8, trailing: 11))
            }
            .buttonStyle(.plain)
            .disabled(model.sending)
            .accessibilityLabel("Attach")
          }
        }
        .padding(6)
        .background(
          .white,
          in: RoundedRectangle(cornerRadius: model.replyTo != nil || input.contains("\n") ? 20 : 30, style: .continuous)
        )
        .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
        .padding(.leading, 13)
        .padding(.trailing, 9)

        Button {
          _ = model.send(input)
        } label: {
          Image("ic_baseline_send_24").renderingMode(.template).resizable().foregroundStyle(.white).padding(8)
            .frame(width: 38, height: 38).background(stateGreen, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.sending)
        .opacity(model.sending ? 0.5 : 1)
        .padding(.trailing, 10)
        .accessibilityLabel("Send")
      }
      if attachmentsOpen { attachmentPanel.transition(.move(edge: .bottom).combined(with: .opacity)) }
    }
    .padding(.bottom, 6)
  }

  private func composerReply(_ model: GroupChatModel, _ m: ChatBubble) -> some View {
    HStack(spacing: 10) {
      RoundedCornersShape(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(Color(hex: 0x28328C)).frame(width: 3)
        .padding(.leading, 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(m.mine ? "You" : m.username).font(.inter(12, .medium)).foregroundStyle(quoteName).lineLimit(1)
        ReplyPreviewText(text: m.previewText())
      }
      Spacer(minLength: 0)
      if m.type == .image, let url = m.url {
        NetImage(url).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
      }
      Button {
        model.replyTo = nil
      } label: {
        Image("cancel").renderingMode(.template).resizable().foregroundStyle(.black).padding(2)
          .frame(width: 20, height: 20).background(.white.opacity(0.7), in: Circle())
      }
      .buttonStyle(.plain)
      .frame(maxHeight: .infinity, alignment: .top)
      .padding(.trailing, 4)
      .accessibilityLabel("Cancel reply")
    }
    .padding(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 10))
    .fixedSize(horizontal: false, vertical: true)
    .background(Color(hex: 0xF5F5F5), in: RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 6)
  }

  /// Camera / Gallery / PDF (chat_gallery_row.xml in a 3-column grid).
  private var attachmentPanel: some View {
    HStack(spacing: 0) {
      ForEach(
        [
          ("Camera", "Take a photo", "ic_camera", Color(hex: 0x4CAF50)),
          ("Gallery", "Choose from gallery", "ic_gallery", Color(hex: 0x9C27B0)),
          ("PDF", "Share a PDF", "ic_document", Color(hex: 0xFF9800)),
        ], id: \.0
      ) { kind, subtitle, icon, color in
        Button {
          attachmentsOpen = false
          switch kind {
          case "Camera":
            if UIImagePickerController.isSourceTypeAvailable(.camera) { takingPhoto = true } else {
              app.show("Camera permission denied")
            }
          case "Gallery": pickingPhoto = true
          default: pickingPDF = true
          }
        } label: {
          VStack(spacing: 2) {
            Image(icon).renderingMode(.template).resizable().frame(width: 28, height: 28).foregroundStyle(.white)
              .frame(width: 40, height: 40).background(color, in: Circle())
            Text(kind).font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x1A1A1A))
            Text(subtitle).font(.inter(9)).foregroundStyle(Color(hex: 0x777777)).multilineTextAlignment(.center)
          }
          .padding(4)
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(8)
    .background(.white, in: RoundedCornersShape(topLeadingRadius: 8, topTrailingRadius: 8))
    .padding(.top, 4)
  }
}

/// SwipeToReplyCallback: drag right (with resistance, max 40% width); past
/// 35% the reply fires once and the row springs back.
private struct SwipeToReply<Content: View>: View {
  let onReply: () -> Void
  @ViewBuilder let content: Content
  @State private var dx: CGFloat = 0
  @State private var triggered = false

  var body: some View {
    content
      .offset(x: dx)
      .background(alignment: .leading) {
        if dx > 0 {
          Image("reply_24px").resizable().frame(width: 24, height: 24).padding(.leading, 16).opacity(min(dx / 120, 1))
        }
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 20)
          .onChanged { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            let max = UIScreen.main.bounds.width * 0.4
            dx = min(Swift.max(value.translation.width * 0.6, 0), max)
            if !triggered, dx / max >= 0.35 {
              triggered = true
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              onReply()
            }
          }
          .onEnded { _ in
            triggered = false
            withAnimation(.spring(duration: 0.2)) { dx = 0 }
          }
      )
  }
}

/// The camera (image_picker ImageSource.camera).
struct CameraPicker: UIViewControllerRepresentable {
  let onImage: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraPicker
    init(_ parent: CameraPicker) { self.parent = parent }

    func imagePickerController(
      _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
  }
}

/// A photo or PDF from the chat, in an in-app browser.
struct SafariView: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}
