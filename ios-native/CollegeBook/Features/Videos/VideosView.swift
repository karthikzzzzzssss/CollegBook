import AVFoundation
import SwiftUI

/// One row of DiscoverFragment: a reels category and its videos.
private struct VideoSection: Identifiable {
  let id: Int
  let title: String
  let cards: [(id: String, thumbnail: String?)]

  init(_ json: JSONObject) {
    let category = json.object("category") ?? [:]
    title = category.string("name") ?? ""
    id = category.int("id") ?? -1
    cards = json.objects("videos").map { ($0.string("id") ?? "", $0["thumbnail"] as? String) }
  }
}

struct ReelsRoute: Hashable {
  let categoryId: Int
  let startId: String?
}

/// The Videos tab — DiscoverFragment (fragment_discover.xml).
struct VideosView: View {
  @EnvironmentObject private var app: AppState
  @State private var sections: [VideoSection]?
  /// The reels player pushed over the tab.
  @State private var playing: ReelsRoute?

  var body: some View {
    CompatNavigationStack {
      VStack(spacing: 0) {
        Text("Videos").font(.inter(17, .bold)).foregroundStyle(.white)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20).padding(.vertical, 15)
          .background(stateGreen)
        ScrollView {
          if sections == nil {
            ProgressView().controlSize(.large).tint(AppColors.primary).frame(maxWidth: .infinity).padding(.top, 200)
          } else if let sections {
            if sections.isEmpty {
              Text("We're working on adding reels — pull down to refresh.").font(.inter(14, .bold)).foregroundStyle(.black)
                .multilineTextAlignment(.center).padding(12).frame(maxWidth: .infinity).padding(.top, 200)
            } else {
              LazyVStack(spacing: 0) {
                ForEach(sections) { section in sectionView(section) }
              }
              .padding(.bottom, 12)
            }
          }
        }
        .pullToRefresh { await load() }
        .background(Color(hex: 0xF5F5F5))
      }
      .background(stateGreen.ignoresSafeArea(edges: .top))
      .hiddenNavigationBar()
      .compatDestination(item: $playing) { ReelsPlayerView(categoryId: $0.categoryId, startId: $0.startId) }
    }
    .task { if sections == nil { await load() } }
  }

  private func load() async {
    do {
      let json = try await app.api.get("reels/landing/")
      sections = (json.object("data") ?? [:]).objects("results").map(VideoSection.init)
    } catch {
      app.show(error.localizedDescription)
      // A failed first load shows the empty message.
      if sections == nil { sections = [] }
    }
  }

  /// item_section.xml.
  private func sectionView(_ section: VideoSection) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(section.title).font(.inter(14, .bold)).foregroundStyle(AppColors.primary)
        Spacer()
        Button {
          playing = ReelsRoute(categoryId: section.id, startId: nil)
        } label: {
          HStack(spacing: 4) {
            Image("ic_play_arrow").renderingMode(.template).resizable().frame(width: 12, height: 12)
            Text("View All").font(.inter(12, .medium))
          }
          .foregroundStyle(AppColors.primary).padding(4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View All \(section.title)")
      }
      .padding(EdgeInsets(top: 0, leading: 10, bottom: 6, trailing: 10))
      ScrollView(.horizontal, showsIndicators: false) {
        // Lazy, so what's on screen isn't queued behind every card of the row.
        LazyHStack(spacing: 0) {
          ForEach(section.cards, id: \.id) { card in
            Button {
              playing = ReelsRoute(categoryId: section.id, startId: card.id)
            } label: {
              NetImage(card.thumbnail).frame(width: 130, height: 180)
                // Shows through while loading or when the thumbnail is missing.
                .background {
                  Image("ic_play_arrow").renderingMode(.template).resizable().frame(width: 28, height: 28)
                    .foregroundStyle(AppColors.primary.opacity(0.35))
                }
                .background(Color(hex: 0xFDF7FD)).clipShape(RoundedRectangle(cornerRadius: 8)).padding(4)
            }
            .buttonStyle(.plain)
            // Otherwise VoiceOver reads the placeholder's image name.
            .accessibilityLabel("Play \(section.title) video")
          }
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
      }
    }
    .padding(EdgeInsets(top: 20, leading: 14, bottom: 10, trailing: 14))
  }
}

// MARK: - Reels player (ReelsPlayerActivity)

final class Reel: Identifiable, ObservableObject {
  let id: String
  let thumbnail: String?
  let caption: String
  let videoFile: String?
  let categoryName: String
  @Published var likesCount: Int
  @Published var liked: Bool
  @Published var bookmarked: Bool

  init(_ json: JSONObject) {
    id = json.string("id") ?? UUID().uuidString
    thumbnail = json["thumbnail"] as? String
    caption = json.string("caption") ?? ""
    videoFile = json["video_file"] as? String
    categoryName = json.object("category")?.string("name") ?? ""
    likesCount = json.int("likes_count") ?? 0
    liked = json.bool("is_liked") == true
    bookmarked = json.bool("is_bookmarked") == true
  }
}

/// A vertical pager of full-screen looping videos for a category (or the
/// recommended feed), paged by cursor five at a time.
struct ReelsPlayerView: View {
  var categoryId = -1
  var startId: String?
  /// newIntentRecommended: reels/recommended/ instead of a category feed.
  var recommended = false

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @State private var reels: [Reel] = []
  @State private var current: String?
  @State private var player: AVPlayer?
  @State private var loopObserver: NSObjectProtocol?
  @State private var playingId: String?
  @State private var playback = Playback.loading
  @State private var observers: [NSKeyValueObservation] = []
  @State private var loadingMore = false
  @State private var userHasDragged = false
  @State private var openedOn: String?
  @State private var nextCursor: String?
  @State private var previousCursor: String?
  @State private var hasNext = false
  @State private var hasPrevious = false

  private static let pageSize = 5

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color.black.ignoresSafeArea()
      // Pages fill the whole screen (a page sized to the safe area let the
      // previous reel peek in under the status bar); overlays keep the insets.
      GeometryReader { geo in
        let insets = geo.safeAreaInsets
        let size = CGSize(width: geo.size.width, height: geo.size.height + insets.top + insets.bottom)
        if #available(iOS 17, *), !Compat.legacy {
          ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
              ForEach(reels) { reel in
                page(reel, bottomInset: insets.bottom).frame(width: size.width, height: size.height).id(reel.id)
              }
            }
            .scrollTargetLayout()
          }
          .scrollTargetBehavior(.paging)
          .scrollPosition(id: $current)
          .ignoresSafeArea()
        } else {
          // Before iOS 17: a paging TabView turned on its side pages vertically.
          TabView(selection: $current) {
            ForEach(reels) { reel in
              page(reel, bottomInset: insets.bottom)
                .frame(width: size.width, height: size.height)
                .rotationEffect(.degrees(-90))
                .frame(width: size.height, height: size.width)
                .tag(reel.id as String?)
            }
          }
          .tabViewStyle(.page(indexDisplayMode: .never))
          .frame(width: size.height, height: size.width)
          .rotationEffect(.degrees(90), anchor: .topLeading)
          .offset(x: size.width)
          .ignoresSafeArea()
        }
      }
      if loadingMore { ProgressView().tint(.white).controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity) }
      Button {
        dismiss()
      } label: {
        Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
          .foregroundStyle(.white).padding(8)
      }
      .accessibilityLabel("Back")
      .padding(12)
    }
    .hiddenNavigationBar()
    .coversTabBar()
    .task { await loadInitial() }
    .onChangeCompat(of: current) { _, id in
      guard let id, let index = reels.firstIndex(where: { $0.id == id }) else { return }
      play(reels[index])
      // A drag gesture on the pager would stop it scrolling, so any move off
      // the reel it opened on counts as the user's swipe.
      if id != openedOn { userHasDragged = true }
      guard userHasDragged else { return }
      Task {
        await loadNextIfNeeded(index)
        await loadPreviousIfNeeded(index)
      }
    }
    .onChangeCompat(of: scenePhase) { _, phase in
      // onPause / onResume.
      if phase == .active { player?.play() } else { player?.pause() }
    }
    .onDisappear { stop() }
  }

  private func page(_ reel: Reel, bottomInset: CGFloat) -> some View {
    ReelPage(
      reel: reel, player: reel.id == playingId ? player : nil,
      playback: reel.id == playingId ? playback : .loading, bottomInset: bottomInset
    ) { like in toggle(reel, like: like) }
  }

  /// `newWindow`: the results replace the list, so both ends follow them.
  /// Otherwise a page moves only its own end: a "next" page's previous cursor
  /// points back into reels already loaded.
  private func fetch(_ direction: String?, _ cursor: String?, newWindow: Bool = false) async -> [Reel]? {
    var query = ["limit": "\(Self.pageSize)"]
    if let direction { query["direction"] = direction }
    if let cursor { query["cursor"] = cursor }
    if recommended { query["page"] = "1" }
    do {
      let json = try await app.api.get(recommended ? "reels/recommended/" : "reels/feed-cursor/\(categoryId)/", query: query)
      guard let data = json.object("data") else { return [] }
      let p = data.object("pagination")
      if direction != "previous" || newWindow {
        hasNext = p?.bool("has_next") == true
        nextCursor = p?["next_cursor"] as? String
      }
      if direction != "next" || newWindow {
        hasPrevious = p?.bool("has_previous") == true
        previousCursor = p?["previous_cursor"] as? String
      }
      return data.objects("results").map(Reel.init)
    } catch {
      // The native player only logs a failed feed load.
      return nil
    }
  }

  /// Reels not in `loaded`: the ids drive the pager, so none may repeat.
  private func unseen(_ incoming: [Reel], in loaded: [Reel]) -> [Reel] {
    var seen = Set(loaded.map(\.id))
    return incoming.filter { seen.insert($0.id).inserted }
  }

  private func loadInitial() async {
    guard reels.isEmpty else { return }
    loadingMore = true
    var loaded = unseen(await fetch(nil, nil) ?? [], in: [])
    // The cursor is exclusive, so asking for "next after the tapped reel"
    // would skip it: page forward from the top until the tapped reel is in.
    if let startId {
      var pages = 1
      while !loaded.contains(where: { $0.id == startId }), hasNext, pages < 10 {
        guard let more = await fetch("next", nextCursor), !more.isEmpty else { break }
        loaded += unseen(more, in: loaded)
        pages += 1
      }
      if !loaded.contains(where: { $0.id == startId }), let after = await fetch("next", startId, newWindow: true) {
        loaded = unseen(after, in: [])
      }
    }
    loadingMore = false
    // Back was pressed: stop() has run, and nothing would stop a player now.
    guard !Task.isCancelled else { return }
    reels = loaded
    if let start = reels.first(where: { $0.id == startId }) ?? reels.first {
      openedOn = start.id
      current = start.id
      play(start)
      // Opened on the last loaded reel there's nothing to swipe to, so no page
      // change would ever load more.
      if start.id == reels.last?.id { await loadNextIfNeeded(reels.count - 1) }
    }
  }

  /// Only from the last loaded reel, once, while the server has more.
  private func loadNextIfNeeded(_ index: Int) async {
    guard index == reels.count - 1, hasNext, !loadingMore else { return }
    loadingMore = true
    let results = await fetch("next", nextCursor)
    loadingMore = false
    reels += unseen(results ?? [], in: reels)
  }

  /// Only from the first loaded reel; keeps the same reel on screen.
  private func loadPreviousIfNeeded(_ index: Int) async {
    guard index == 0, hasPrevious, !loadingMore else { return }
    loadingMore = true
    let results = await fetch("previous", previousCursor)
    loadingMore = false
    let older = unseen(results ?? [], in: reels)
    guard !older.isEmpty else { return }
    let keep = current
    reels.insert(contentsOf: older, at: 0)
    current = keep
  }

  private func stop() {
    player?.pause()
    player = nil
    if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
    loopObserver = nil
    observers.forEach { $0.invalidate() }
    observers = []
  }

  /// One looping video at a time (setLooping(true)); a failed reel stays on
  /// its thumbnail.
  private func play(_ reel: Reel) {
    guard reel.id != playingId else { return }
    stop()
    playingId = reel.id
    guard let file = reel.videoFile, let url = URL(string: file) else { return playback = .failed }
    playback = .loading
    let item = AVPlayerItem(url: url)
    let next = AVPlayer(playerItem: item)
    // A missing file (the CDN answers 404) fails the item; otherwise the
    // spinner stays until frames are actually playing.
    observers = [
      item.observe(\.status) { item, _ in
        guard item.status == .failed else { return }
        Task { @MainActor in if playingId == reel.id { playback = .failed } }
      },
      next.observe(\.timeControlStatus) { player, _ in
        let state: Playback = player.timeControlStatus == .playing ? .playing : .loading
        Task { @MainActor in if playingId == reel.id, playback != .failed { playback = state } }
      },
    ]
    loopObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
    ) { [weak next] _ in
      next?.seek(to: .zero)
      next?.play()
    }
    try? AVAudioSession.sharedInstance().setCategory(.playback)
    player = next
    next.play()
  }

  private func toggle(_ reel: Reel, like: Bool) {
    let now = like ? !reel.liked : !reel.bookmarked
    if like {
      reel.liked = now
      reel.likesCount = max(reel.likesCount + (now ? 1 : -1), 0)
    } else {
      reel.bookmarked = now
    }
    Task {
      do {
        try await app.api.request(
          "POST", like ? "reels/like/" : "reels/bookmark/",
          body: ["reel_id": reel.id, "action": like ? (now ? "like" : "unlike") : (now ? "bookmark" : "unbookmark")])
      } catch {
        if like {
          reel.liked = !now
          reel.likesCount += now ? -1 : 1
        } else {
          reel.bookmarked = !now
        }
      }
    }
  }
}

enum Playback { case loading, playing, failed }

/// item_reel_video.xml.
private struct ReelPage: View {
  @ObservedObject var reel: Reel
  let player: AVPlayer?
  let playback: Playback
  var bottomInset: CGFloat = 0
  let onToggle: (Bool) -> Void

  var body: some View {
    ZStack {
      Color.black
      // Under the video, so a reel whose file fails still shows its picture.
      if let thumb = reel.thumbnail { NetImage(thumb) }
      if let player, playback != .failed { PlayerLayerView(player: player) }
      switch playback {
      case .loading: ProgressView().tint(.white).controlSize(.large)
      case .playing: EmptyView()
      case .failed:
        VStack(spacing: 10) {
          Image("ic_play_arrow").renderingMode(.template).resizable().frame(width: 28, height: 28)
            .foregroundStyle(.white.opacity(0.8)).padding(18).background(.black.opacity(0.45), in: Circle())
          Text("This video is unavailable right now").font(.inter(14, .medium)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 2)
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Spacer()
        Text(reel.categoryName).font(.inter(14, .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 2)
        Text(reel.caption).font(.inter(13, .medium)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .padding(.trailing, 72)
      .padding(.bottom, bottomInset)
      VStack(spacing: 0) {
        Spacer()
        disc("Like", reel.liked ? "ic_heart_filled" : "ic_heart_outline", reel.liked ? Color(hex: 0xFF3B5C) : .white, 11) {
          onToggle(true)
        }
        Text("\(reel.likesCount)").font(.inter(12, .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 2)
          .padding(.top, 4)
        disc("Save", "ic_bookmark_outline", reel.bookmarked ? Color(hex: 0xFFC107) : .white, 12) { onToggle(false) }
          .padding(.top, 18)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.trailing, 12).padding(.bottom, 16 + bottomInset)
    }
    .clipped()
  }

  /// bg_reel_action: a 48pt translucent dark disc behind the icon.
  private func disc(_ label: String, _ icon: String, _ tint: Color, _ padding: CGFloat, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(icon).renderingMode(.template).resizable().foregroundStyle(tint).padding(padding)
        .frame(width: 48, height: 48).background(.black.opacity(0.35), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// resize_mode="zoom": the video fills its page, cropping the overflow.
private struct PlayerLayerView: UIViewRepresentable {
  let player: AVPlayer

  final class LayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }

  func makeUIView(context: Context) -> LayerView {
    let view = LayerView()
    view.playerLayer.videoGravity = .resizeAspectFill
    view.playerLayer.player = player
    return view
  }

  func updateUIView(_ view: LayerView, context: Context) { view.playerLayer.player = player }
}
