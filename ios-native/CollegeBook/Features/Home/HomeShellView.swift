import SwiftUI

/// The six bottom-nav tabs (CollegeHomePageActivity).
enum HomeTab: Int, CaseIterable, Identifiable {
  case home, cutoff, mentor, videos, community, premium

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .cutoff: "Cutoff"
    case .mentor: "Mentor"
    case .videos: "Videos"
    case .community: "Community"
    case .premium: "Premium"
    }
  }

  /// assets/icons/nav/<icon>_select|unselect.svg
  var icon: String {
    switch self {
    case .home: "ic_baseline_college_home"
    case .cutoff: "ic_baseline_college_package"
    case .mentor: "ic_baseline_college_skill"
    case .videos: "ic_baseline_college_call"
    case .community: "ic_baseline_college_community"
    case .premium: "ic_premium"
    }
  }
}

/// lib/features/home/home_shell.dart: the tabs, kept alive like the Flutter
/// IndexedStack, the bottom nav and the side menu.
struct HomeShellView: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.scenePhase) private var scenePhase
  @State private var selected: HomeTab = .home
  /// Tabs load the first time they are opened, then stay alive. Videos is
  /// built hidden from the start (as the Flutter IndexedStack built every
  /// tab), so its sections and thumbnails are ready when it is tapped.
  @State private var visited: Set<HomeTab> = [.home, .videos]
  @State private var menuOpen = false
  /// The Cutoff tab's sub-tab: 0 Colleges, 1 CutOffs & Matchings, 2 Allotments.
  @State private var collegeTab = 0
  /// CollegePackagesActivity, for "Get a Package" / "Go Premium to Apply".
  @State private var showPackages = false
  @State private var tabBarHidden = false
  @State private var confirmLogout = false
  @State private var loggingOut = false
  @State private var confirmDelete = false
  @State private var deletingAccount = false
  /// college/membership/: every tab treats the user as free until it says otherwise.
  @State private var isSubscribed = false

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        ZStack {
          // Visited tabs stay alive (like the Flutter IndexedStack); the
          // selected one is drawn on top so the status bar reads its header.
          ForEach(HomeTab.allCases.filter { visited.contains($0) }) { tab in
            TabHost(hidden: tab != selected) {
              page(tab).environmentObject(app).environment(\.scenePhase, scenePhase)
            }
            // Up to the screen's top edge, so each tab's green header colour
            // fills the status bar (its content still lays out below it).
            .ignoresSafeArea(.container, edges: .top)
            .opacity(tab == selected ? 1 : 0)
            .zIndex(tab == selected ? 1 : 0)
            .allowsHitTesting(tab == selected)
            .accessibilityHidden(tab != selected)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        if !tabBarHidden { BottomNavBar(selected: $selected) }
      }
      .background(AppColors.canvas)
      .ignoresSafeArea(.container, edges: .bottom)
      // The keyboard covers the bottom bar, like a UITabBar; each tab's own
      // hosting view moves its content (a chat box) clear of the keyboard.
      .ignoresSafeArea(.keyboard, edges: .bottom)

      SideMenu(isOpen: $menuOpen, onLogout: { confirmLogout = true }, onDeleteAccount: { confirmDelete = true })

      if loggingOut || deletingAccount {
        Color.black.opacity(0.3).ignoresSafeArea()
        HStack(spacing: 20) {
          ProgressView()
          Text(deletingAccount ? "Deleting account..." : "Logging out...").font(.inter(15))
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
      }
    }
    .fullScreenCover(isPresented: $showPackages) {
      CompatNavigationStack { PackagesView { Task { await loadMembership() } } }
    }
    .alert("Logout", isPresented: $confirmLogout) {
      Button("Cancel", role: .cancel) {}
      Button("Logout", role: .destructive, action: logout)
    } message: {
      Text("Are you sure you want to logout?")
    }
    .alert("Delete Account", isPresented: $confirmDelete) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive, action: deleteAccount)
    } message: {
      Text("Your account and its data will be permanently deleted, including any wallet balance and membership. This can't be undone.")
    }
    .task {
      // Mentor calls (CallKit); a fresh PushKit token goes to the server.
      CallCoordinator.shared.start(app: app)
      await NotificationSync.checkAndSync(promptShownThisRun: app.notificationPromptShownThisRun)
    }
    // Its own task: the sync above can wait on the user answering a prompt.
    .task { await loadMembership() }
    .onChangeCompat(of: app.coveringScreens) { _, count in
      // Hide at once; show again only once no screen has covered it for a
      // moment (a push swaps one covering screen for another).
      if count > 0 { return tabBarHidden = true }
      Task {
        try? await Task.sleep(seconds: 0.3)
        if app.coveringScreens == 0 { tabBarHidden = false }
      }
    }
    .onChangeCompat(of: scenePhase) { _, phase in
      if phase == .active {
        CallCoordinator.shared.showWaiting()
        Task { await NotificationSync.checkAndSync(promptShownThisRun: app.notificationPromptShownThisRun) }
        Task { await loadMembership() }
      }
    }
    .onChangeCompat(of: selected) { _, tab in visited.insert(tab) }
  }

  /// Each tab keeps its own navigation stack, like the Flutter tabs did.
  @ViewBuilder
  private func page(_ tab: HomeTab) -> some View {
    switch tab {
    case .home:
      HomeView(
        isSubscribed: isSubscribed,
        openCutoffTab: { collegeTab = $0; selected = .cutoff },
        openMenu: { menuOpen = true },
        openPackages: { showPackages = true })
    case .mentor:
      MentorView()
    case .community:
      CommunityView()
    case .videos:
      VideosView()
    case .premium:
      PremiumView { Task { await loadMembership() } }
    case .cutoff:
      CutoffView(
        isSubscribed: isSubscribed,
        selectedTab: $collegeTab,
        openMentor: { selected = .mentor },
        openPremium: { selected = .premium },
        openPackages: { showPackages = true })
    }
  }

  private func loadMembership() async {
    // Server down: the native app falls back to a free (unsubscribed) model.
    if let data = try? await app.api.object("college/membership/") {
      isSubscribed = data.bool("is_subscribed") ?? false
    }
  }

  private func logout() {
    loggingOut = true
    Task {
      if app.session.accessToken != nil {
        await goOfflineIfMentor()
        // Read only now: the call above may have refreshed the token.
        if let access = app.session.accessToken {
          await AuthAPI().logout(access: access, refresh: app.session.refreshToken)
        }
      }
      loggingOut = false
      app.signOut()
    }
  }

  /// auth/account/delete/. The session only ends once the server has done it;
  /// a failure leaves the user logged in, with the reason.
  private func deleteAccount() {
    deletingAccount = true
    Task {
      defer { deletingAccount = false }
      await goOfflineIfMentor()
      do {
        let json = try await app.api.request("DELETE", "auth/account/delete/")
        app.signOut()
        app.show(json.string("description") ?? "Your account has been deleted.")
      } catch {
        app.show(error.localizedDescription.isEmpty ? "Couldn't delete your account. Please try again." : error.localizedDescription)
      }
    }
  }

  /// A mentor who logs out stops taking calls: "Available for calls" is
  /// switched off first, while the login still works. Best effort, and never
  /// holds up the logout for more than a few seconds.
  private func goOfflineIfMentor() async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask { @MainActor in
        // Like As a Mentor: the status can come back as an error's payload.
        var json: JSONObject?
        do {
          json = try await app.api.get("college/counsellor/")
        } catch let error as APIError {
          json = error.payload
        } catch {}
        let available = json?.object("data")?.bool("is_available") == true
        #if DEBUG
          NSLog("Logout: mentor status %@, available %d", json?.string("message") ?? "nil", available ? 1 : 0)
        #endif
        guard json?.string("message") == "COUNSELLOR_PROFILE", available else { return }
        do {
          try await app.api.request("PUT", "college/counsellor/profile/", body: ["is_available": false])
          #if DEBUG
            NSLog("Logout: availability turned off")
          #endif
        } catch {
          #if DEBUG
            NSLog("Logout: turning availability off failed: %@", String(describing: error))
          #endif
        }
      }
      group.addTask { try? await Task.sleep(seconds: 8) }
      await group.next()
      group.cancelAll()
    }
  }
}

/// A tab in its own UIKit hosting view, so a hidden tab can be taken out of
/// VoiceOver: accessibilityHidden doesn't reach into the tab's UIKit-backed
/// NavigationStack, and VoiceOver read hidden tabs' buttons. SwiftUI resets
/// flags on the views it manages, so the hosting view sits in a plain hidden
/// shield no one else touches, under a container view that keeps its answers.
/// All of it lives as long as the tab, so its state is kept.
private struct TabHost<Content: View>: UIViewControllerRepresentable {
  let hidden: Bool
  @ViewBuilder let content: () -> Content

  func makeUIViewController(context: Context) -> Container {
    let container = Container(host: UIHostingController(rootView: content()))
    container.setHidden(hidden)
    return container
  }

  func updateUIViewController(_ container: Container, context: Context) {
    container.host.rootView = content()
    container.setHidden(hidden)
  }

  final class Container: UIViewController {
    let host: UIHostingController<Content>
    private let shield = UIView()

    init(host: UIHostingController<Content>) {
      self.host = host
      super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() { view = TabContainerView(frame: UIScreen.main.bounds) }

    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      host.view.backgroundColor = .clear
      shield.frame = view.bounds
      shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(shield)
      addChild(host)
      host.view.frame = shield.bounds
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      shield.addSubview(host.view)
      host.didMove(toParent: self)
    }

    /// A hidden view is out of VoiceOver entirely; the tab stays alive.
    func setHidden(_ hidden: Bool) {
      loadViewIfNeeded()
      shield.isHidden = hidden
      shield.accessibilityElementsHidden = hidden
      (view as? TabContainerView)?.tabHidden = hidden
    }
  }
}

/// Answers accessibility from the tab's state, whatever SwiftUI sets on it.
private final class TabContainerView: UIView {
  var tabHidden = false

  override var accessibilityElementsHidden: Bool {
    get { tabHidden }
    set {}
  }

  override var accessibilityElements: [Any]? {
    get { tabHidden ? [] : nil }
    set {}
  }
}
