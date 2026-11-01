import SwiftUI

private let mentorSecondary = Color(hex: 0x6B7280)
private let mentorStroke = Color(hex: 0xE3E5E8)
private let mentorCanvas = Color(hex: 0xF6FAF7)

/// One mentor from college/counsellor-list/ (CollegePlanCounselorModel.Result).
final class Mentor: Identifiable, ObservableObject {
  let id: String
  let name: String
  let image: String?
  let speciality: String?
  let designation: String
  let instituteName: String
  let degree: String
  let available: Bool?
  @Published var liked: Bool
  let expertise: [String]
  let fee: String
  let duration: String

  init(_ json: JSONObject) {
    id = json.string("id") ?? ""
    name = json["name"] as? String ?? ""
    image = json["image"] as? String
    speciality = json["speciality"] as? String
    designation = (json["designation"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    instituteName = json["institute_name"] as? String ?? ""
    degree = (json["degree"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    var available = json["is_available"] as? Bool
    #if DEBUG
      // `-mentorsOffline YES`: every mentor offline, to check that card.
      if UserDefaults.standard.bool(forKey: "mentorsOffline") { available = false }
    #endif
    self.available = available
    liked = json.bool("like_status") == true
    expertise = json.objects("expert").compactMap { $0.string("name") }
    let appointment = json.object("appointment") ?? [:]
    fee = appointment.string("consultation_fee") ?? "0"
    duration = appointment.string("duration") ?? ""
  }
}

enum MentorRoute: Hashable {
  case favourites, wallet
}

/// The Mentor tab — CollegePGTalkFragment (fragment_college_p_g_talk.xml).
struct MentorView: View {
  @EnvironmentObject private var app: AppState
  @State private var mentors: [Mentor] = []
  @StateObject private var filters = MentorFilters()
  @State private var page = 1
  @State private var totalPages = 1
  @State private var request = 0
  @State private var loading = false
  @State private var loaded = false
  @State private var expanded = false
  @State private var searching = false
  /// Favourites or Wallet, pushed over the tab.
  @State private var route: MentorRoute?
  @State private var favouritesChanged = false

  private static let pageLimit = 10

  var body: some View {
    CompatNavigationStack {
      VStack(spacing: 0) {
        header
        ZStack {
          if loaded {
            ScrollViewReader { proxy in
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                  hero.id("top")
                  if !isEmpty {
                    Text("Available mentors").font(.inter(16, .semibold)).foregroundStyle(appInk)
                      .padding(EdgeInsets(top: 20, leading: 16, bottom: 6, trailing: 16))
                  }
                  ForEach(Array(mentors.enumerated()), id: \.element.id) { index, mentor in
                    MentorCard(mentor: mentor)
                      .onAppear {
                        // Native: next page once scrolled to the end.
                        if index == mentors.count - 1, !loading, page < totalPages {
                          page += 1
                          loading = true
                          Task { await load(fresh: false) }
                        }
                      }
                  }
                }
                .padding(.bottom, 16)
              }
              .pullToRefresh { await load(fresh: true) }
              .onChangeCompat(of: request) { _, _ in if page == 1 { proxy.scrollTo("top", anchor: .top) } }
            }
          }
          if isEmpty {
            Text(filters.hasApplied ? "No mentors match your search." : "No PG talks available at the moment.")
              .font(.inter(15, .medium)).foregroundStyle(mentorSecondary).multilineTextAlignment(.center)
          }
          if loading, page == 1 { ProgressView().tint(.black).controlSize(.large) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(mentorCanvas)
      }
      .background(stateGreen.ignoresSafeArea(edges: .top))
      .hiddenNavigationBar()
      .compatDestination(item: $route) { route in
        switch route {
        case .favourites: FavouriteMentorsView(changed: $favouritesChanged)
        case .wallet: WalletView(onDone: { self.route = nil })
        }
      }
      .sheet(isPresented: $searching) {
        SearchMentorSheet(filters: filters) { Task { await load(fresh: true) } }
      }
    }
    .task {
      guard !loaded else { return }
      await load(fresh: true)
    }
    .onChangeCompat(of: route == nil) { _, atRoot in
      // Back from Favourites with changes: reload.
      if atRoot, favouritesChanged {
        favouritesChanged = false
        Task { await load(fresh: true) }
      }
    }
  }

  private var isEmpty: Bool { loaded && !loading && mentors.isEmpty }

  private func load(fresh: Bool) async {
    if fresh { page = 1 }
    request += 1
    let current = request
    loading = true
    defer {
      if current == request {
        loading = false
        loaded = true
      }
    }
    do {
      let json = try await app.api.request(
        "POST", "college/counsellor-list/",
        body: [
          "states": filters.applied[0], "institute_names": filters.applied[1], "specialities": filters.applied[2],
          "degrees": filters.applied[3], "page": page, "limit": Self.pageLimit,
        ])
      guard current == request else { return }
      let data = json.object("data") ?? [:]
      totalPages = data.int("total_page") ?? 1
      let results = data.objects("results").map(Mentor.init)
      mentors = fresh ? results : mentors + results
    } catch let error as APIError where error.isCancelled {
      // Not a failure: keep what is shown.
      if !fresh, current == request { page -= 1 }
    } catch {
      guard current == request else { return }
      if fresh { mentors = [] } else { page -= 1 }
      app.show("Failed to load counsellors")
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text("Mentor").font(.inter(17, .bold)).foregroundStyle(.white)
      Spacer()
      headerBox("Search", "ic_baseline_search_24", stateGreen) { searching = true }
      headerBox("Favourites", "ic_heart_filled", AppColors.primary) { route = .favourites }
      headerBox("Wallet", "connect_premium_selected", stateGreen) { route = .wallet }
    }
    .padding(.leading, 20)
    .padding(.vertical, 12)
    .background(stateGreen)
  }

  private func headerBox(_ label: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(icon).renderingMode(.template).resizable().frame(width: 20, height: 20).foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(AppColors.allIndia, in: RoundedRectangle(cornerRadius: 4))
        // Up to the 12pt gaps between the boxes, so a tap can't hit the wrong one.
        .extendedTapArea(horizontal: 6, vertical: 8)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .padding(.trailing, label == "Wallet" ? 12 : 0)
  }

  private static let heroText =
    "Get real, verified hospital insights from current residents and faculty — including daily OPD load, MRI/CT/Ultrasound availability, surgery volume, hospital and ICU beds, monthly deliveries, academic exposure, and branchwise clinical performance — to make better NEET PG choice filling decisions."

  private var hero: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Talk Directly with PGs & Faculty").font(.inter(18, .bold)).foregroundStyle(stateGreen)
      Text(Self.heroText).font(.inter(13)).foregroundStyle(Color(hex: 0x4B5563)).lineSpacing(5)
        .lineLimit(expanded ? nil : 3)
      Button(expanded ? "Read less" : "Read more") { expanded.toggle() }
        .font(.inter(13, .semibold)).foregroundStyle(stateGreen).padding(.vertical, 2)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: 0xEAF4EE), in: RoundedRectangle(cornerRadius: 16))
    .padding(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
  }
}

/// row_listof_counselor.xml with ListOfCounselorsAdapter's behaviour.
struct MentorCard: View {
  @ObservedObject var mentor: Mentor
  /// Favourites screen: un-liking removes the card.
  var onFavouriteChanged: ((Mentor, Bool) -> Void)? = nil

  @EnvironmentObject private var app: AppState
  @State private var expanded = false
  private static let collapsed = 3

  var body: some View {
    let m = mentor
    let college = m.speciality.map { "\($0) • \(m.instituteName)" } ?? m.instituteName
    let location = m.degree.isEmpty ? college : "\(college) • \(m.degree)"
    let shown = expanded ? m.expertise.count : min(m.expertise.count, Self.collapsed)
    let hidden = m.expertise.count - shown
    // Only an explicit "offline" from the server greys the card out.
    let offline = m.available == false
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        ZStack(alignment: .topLeading) {
          NetImage(m.image, placeholder: "home_iv_mirror").frame(width: 92, height: 112).clipped()
            // Offline: the photo washed out.
            .saturation(offline ? 0.5 : 1)
            .overlay(Color.white.opacity(offline ? 0.45 : 0))
          if let available = m.available { availability(available).padding(6) }
        }
        .frame(width: 92, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12))

        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 4) {
              Text(m.name).font(.inter(16, .bold)).foregroundStyle(appInk).lineLimit(1)
              Image("ic_verified").resizable().frame(width: 16, height: 16)
            }
            Spacer(minLength: 0)
            Button(action: toggleFavourite) {
              Image(m.liked ? "ic_heart_filled" : "ic_heart_outline").renderingMode(.template).resizable()
                .frame(width: 22, height: 22)
                .foregroundStyle(m.liked ? AppColors.primary : mentorSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(m.liked ? "Remove from favourites" : "Add to favourites")
          }
          if !m.designation.isEmpty {
            Text(m.designation).font(.inter(13, .semibold)).foregroundStyle(stateGreen).padding(.top, 2)
          }
          HStack(alignment: .top, spacing: 6) {
            Image("ic_building").renderingMode(.template).resizable().frame(width: 14, height: 14)
              .foregroundStyle(mentorSecondary).padding(.top, 2)
            Text(location).font(.inter(12, .medium)).foregroundStyle(mentorSecondary).lineSpacing(3)
          }
          .padding(.top, 6)
          // The native layout's fixed text (the adapter never sets it).
          Text("⭐ 4.9 (256)   👥 320 Students Guided ").font(.inter(12, .medium)).foregroundStyle(appInk)
            .padding(.top, 6)
        }
      }

      if !m.expertise.isEmpty {
        FlowStack(spacing: 6, lineSpacing: 6) {
          ForEach(0..<shown, id: \.self) { chip(m.expertise[$0]) }
          if hidden > 0 || (expanded && m.expertise.count > Self.collapsed) {
            Button {
              expanded = hidden > 0
            } label: {
              chip(hidden > 0 ? "+\(hidden) more" : "Show less", more: true)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.top, 10)
      }

      if offline {
        // Can't be called while offline: a grey, inactive bar.
        HStack(spacing: 8) {
          Image("phone_in_talk").renderingMode(.template).resizable().frame(width: 18, height: 18)
          Text("Currently offline").font(.inter(15, .semibold))
        }
        .foregroundStyle(mentorSecondary)
        .frame(maxWidth: .infinity).frame(height: 46)
        .background(Color(hex: 0xE5E7EB), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.name) is currently offline")
        .padding(.top, 14)
      } else {
        Button {
          Task { await confirmAndCallMentor(m, app: app) }
        } label: {
          HStack(spacing: 8) {
            Image("phone_in_talk").resizable().frame(width: 18, height: 18)
            Text("Call now ₹\(m.fee) (\(m.duration))").font(.inter(15, .semibold)).foregroundStyle(.white)
          }
          .frame(maxWidth: .infinity).frame(height: 46)
          .background(stateGreen, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
      }
    }
    .padding(14)
    .background(.white, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(mentorStroke))
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
  }

  private func chip(_ text: String, more: Bool = false) -> some View {
    Text(text).font(.inter(11, .medium)).lineLimit(1)
      .foregroundStyle(more ? .white : stateGreen)
      .padding(.horizontal, 10).padding(.vertical, 4)
      .background(more ? stateGreen : Color(hex: 0xEEF5F1), in: Capsule())
  }

  private func availability(_ available: Bool) -> some View {
    HStack(spacing: 4) {
      Circle().fill(available ? Color(hex: 0x22C55E) : Color(hex: 0x9CA3AF)).frame(width: 6, height: 6)
      Text(available ? "Online" : "Offline").font(.inter(9, .semibold))
        .foregroundStyle(available ? Color(hex: 0x15803D) : mentorSecondary)
    }
    .padding(.horizontal, 7).padding(.vertical, 2)
    .background(available ? Color(hex: 0xDCFCE7) : Color(hex: 0xF3F4F6), in: Capsule())
    .overlay(Capsule().stroke(available ? Color(hex: 0x86EFAC) : mentorStroke))
  }

  /// The heart flips at once; it flips back if the server refuses.
  private func toggleFavourite() {
    let liked = !mentor.liked
    mentor.liked = liked
    onFavouriteChanged?(mentor, liked)
    Task {
      do {
        try await app.api.request(
          "POST", "college/fevorite-counsellor/", body: ["counsellor_id": mentor.id, "like_status": liked])
        app.show(liked ? "Added to favourites" : "Removed from favourites")
      } catch {
        mentor.liked = !liked
        onFavouriteChanged?(mentor, !liked)
        let offline = (error as? APIError)?.statusCode == nil
        app.show(
          offline
            ? "Check your internet and try again."
            : (liked ? "Couldn't add to favourites" : "Couldn't remove from favourites"))
      }
    }
  }
}

// MARK: - Favourite Mentors (FavoriteCounsellorsActivity)

struct FavouriteMentorsView: View {
  @Binding var changed: Bool

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var mentors: [Mentor] = []
  @State private var page = 1
  @State private var totalPages = 1
  @State private var request = 0
  @State private var loading = false
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 22, height: 22)
            .foregroundStyle(.white).padding(9)
        }
        .accessibilityLabel("Back")
        Text("Favourite Mentors").font(.inter(17, .bold)).foregroundStyle(.white)
        Spacer()
      }
      .padding(.leading, 4)
      .frame(minHeight: 56)
      .background(stateGreen)

      ZStack {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(mentors.enumerated()), id: \.element.id) { index, mentor in
              MentorCard(mentor: mentor) { m, liked in
                changed = true
                if !liked {
                  mentors.removeAll { $0.id == m.id }
                } else if !mentors.contains(where: { $0.id == m.id }) {
                  mentors.append(m)
                }
              }
              .onAppear {
                if index >= mentors.count - 2, !loading, page < totalPages {
                  page += 1
                  loading = true
                  Task { await load(fresh: false) }
                }
              }
            }
          }
          .padding(.top, 12).padding(.bottom, 16)
        }
        .pullToRefresh { await load(fresh: true) }

        if !loading, mentors.isEmpty {
          VStack(spacing: 0) {
            Image("ic_heart_outline").renderingMode(.template).resizable().foregroundStyle(AppColors.primary)
              .padding(18).frame(width: 64, height: 64).background(Color(hex: 0xE6EEEA), in: Circle())
            Text(error != nil ? "Couldn't load favourites" : "No favourite mentors yet").font(.inter(16, .semibold))
              .foregroundStyle(appInk).padding(.top, 16)
            Text(error ?? "Tap the heart on a mentor's card to save them here.").font(.inter(13))
              .foregroundStyle(mentorSecondary).multilineTextAlignment(.center).padding(.top, 6)
          }
          .padding(.horizontal, 32)
        }
        if loading, mentors.isEmpty { ProgressView().tint(.black).controlSize(.large) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(mentorCanvas)
    }
    .background(stateGreen.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
    .task { await load(fresh: true) }
  }

  private func load(fresh: Bool) async {
    if fresh { page = 1 }
    request += 1
    let current = request
    loading = true
    defer { if current == request { loading = false } }
    do {
      let data = try await app.api.object("college/fevorite-counsellor/", query: ["page": "\(page)", "limit": "10"])
      guard current == request else { return }
      error = nil
      totalPages = data.int("total_page") ?? 1
      let results = data.objects("results").map(Mentor.init)
      mentors = fresh ? results : mentors + results
    } catch {
      guard current == request else { return }
      if !fresh { page -= 1 }
      let message = "Couldn't load your favourite mentors"
      if mentors.isEmpty { self.error = message } else { app.show(message) }
    }
  }
}

// MARK: - Find a Mentor sheet

/// The selections and option lists, kept across sheet openings like the
/// native fragment's fields.
@MainActor final class MentorFilters: ObservableObject {
  static let hints = ["Select States", "Select Colleges", "Select Specializations", "Select Degrees"]

  /// states, colleges, specialities, degrees.
  @Published var options: [[FilterOption]] = [
    [], [], [], ["DNB", "Diploma", "M.Ch", "MD", "MS", "Nbems DMRD"].map { FilterOption($0, false) },
  ] {
    didSet { adopt() }
  }
  /// What the list is filtered by (sent as states, institute_names, ...).
  @Published var applied: [[String]] = [[], [], [], []]
  @Published var loadingStates = false
  @Published var loadingSpecs = false
  @Published var loadingColleges = false
  @Published var collegesRequest = 0

  var hasApplied: Bool { applied.contains { !$0.isEmpty } }

  init() { adopt() }

  /// Options redraw this state's views when they change.
  private func adopt() {
    for list in options { for option in list { option.willChange = { [weak self] in self?.objectWillChange.send() } } }
  }

  func selected(_ index: Int) -> [String] { options[index].filter(\.selected).map(\.name) }
}

private struct SearchMentorSheet: View {
  @ObservedObject var filters: MentorFilters
  let onApply: () -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var open: Int?

  private var f: MentorFilters { filters }

  private var canSubmit: Bool { (0..<4).contains { !f.selected($0).isEmpty } || f.hasApplied }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Text("Find a Mentor").font(.inter(20, .bold)).foregroundStyle(AppColors.primary)
        Spacer()
        Button("Clear all") {
          for list in f.options { for o in list { o.selected = false } }
          open = nil
          reloadColleges()
        }
        .font(.inter(14, .semibold)).foregroundStyle(stateGreen)
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_close").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(.black)
        }
        .accessibilityLabel("Close")
      }
      .padding(EdgeInsets(top: 26, leading: 20, bottom: 0, trailing: 20))
      Text("Get college & branch insights directly from seniors living your dream seat").font(.inter(13))
        .foregroundStyle(Color(hex: 0x5F6B66)).padding(EdgeInsets(top: 4, leading: 20, bottom: 14, trailing: 20))
      Rectangle().fill(Color(hex: 0xE6E6E6)).frame(height: 1)

      ScrollView {
        VStack(spacing: 0) {
          ForEach(0..<4, id: \.self) { i in
            field(i)
            if open == i { optionsCard(i) }
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
      }

      Button {
        for i in 0..<4 { f.applied[i] = f.selected(i) }
        onApply()
        dismiss()
      } label: {
        Text("Submit").font(.inter(16, .semibold)).foregroundStyle(.white)
          .frame(maxWidth: .infinity).frame(height: 50)
          .background(stateGreen, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(!canSubmit)
      .opacity(canSubmit ? 1 : 0.4)
      .padding(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
    }
    .background(.white)
    .sheetDetents([.fraction(0.85)])
    .sheetDragIndicatorVisible()
    .sheetCornerRadius(18)
    .onAppear(perform: loadOptions)
  }

  /// layout_mentor_filter_field: an outlined dropdown whose label sits on the
  /// top border once it is open or has a value.
  private func field(_ i: Int) -> some View {
    let value = summary(i)
    let showLabel = open == i || !value.isEmpty
    return Button {
      tapField(i)
    } label: {
      HStack {
        Text(showLabel ? value : MentorFilters.hints[i]).font(.inter(15)).foregroundStyle(stateGreen).lineLimit(1)
        Spacer()
        Image("ic_baseline_arrow_drop_down_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
          .foregroundStyle(stateGreen).rotationEffect(.degrees(open == i ? 180 : 0))
      }
      .padding(.leading, 16).padding(.trailing, 12)
      .frame(height: 52)
      .background(Color(hex: 0xF4F9F1), in: RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8).stroke(open == i ? stateGreen : Color(hex: 0xC9D3BF), lineWidth: open == i ? 2 : 1)
      )
      .overlay(alignment: .topLeading) {
        if showLabel {
          Text(MentorFilters.hints[i]).font(.inter(12, .medium)).foregroundStyle(stateGreen)
            .padding(.horizontal, 4)
            .background(
              LinearGradient(stops: [.init(color: .white, location: 0.5), .init(color: Color(hex: 0xF4F9F1), location: 0.5)],
                startPoint: .top, endPoint: .bottom)
            )
            .offset(x: 12, y: -8)
        }
      }
    }
    .buttonStyle(.plain)
    .padding(.top, 18)
  }

  /// popup_mentor_filter_options: a card of checkbox rows under the field.
  private func optionsCard(_ i: Int) -> some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(f.options[i]) { option in
          Button {
            option.selected.toggle()
            if i == 0 { reloadColleges() }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: option.selected ? "checkmark.square.fill" : "square").font(.system(size: 20))
                .foregroundStyle(stateGreen)
              Text(option.name).font(.inter(15)).foregroundStyle(.black).multilineTextAlignment(.leading)
              Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.vertical, 4)
    }
    .frame(maxHeight: 300)
    .fixedSize(horizontal: false, vertical: f.options[i].count < 7)
    .background(.white, in: RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xDCE3D8)))
    .shadow(color: .black.opacity(0.13), radius: 6, y: 3)
    .padding(.top, 4)
  }

  private func summary(_ i: Int) -> String {
    let s = f.selected(i)
    if s.isEmpty { return "" }
    if s.count <= 2 { return s.joined(separator: ", ") }
    return "\(s[0]) +\(s.count - 1) more"
  }

  private func tapField(_ i: Int) {
    if open == i {
      open = nil
      return
    }
    if f.options[i].isEmpty {
      app.show(
        i == 0 ? "Loading states…" : i == 1 ? (f.loadingColleges ? "Loading colleges…" : "No colleges found") : "Loading specializations…")
      loadOptions()
      return
    }
    open = i
  }

  private func fetch(_ method: String, _ endpoint: String, _ body: JSONObject? = nil) async -> [FilterOption] {
    guard let json = try? await app.api.request(method, endpoint, body: body) else { return [] }
    return (json.object("data") ?? [:]).objects("results").compactMap { $0.string("name") }.map { FilterOption($0, false) }
  }

  /// States and specializations load once; a failed load retries later.
  private func loadOptions() {
    if f.options[0].isEmpty, !f.loadingStates {
      f.loadingStates = true
      Task {
        f.options[0] = await fetch("GET", "college/counsellor/drop-down/state/")
        f.loadingStates = false
      }
    }
    if f.options[1].isEmpty, !f.loadingColleges { reloadColleges() }
    if f.options[2].isEmpty, !f.loadingSpecs {
      f.loadingSpecs = true
      Task {
        f.options[2] = await fetch("GET", "college/counsellor/drop-down/speciality/")
        f.loadingSpecs = false
      }
    }
  }

  /// All colleges with no state picked, else the picked states' institutes;
  /// colleges still listed stay ticked.
  private func reloadColleges() {
    f.collegesRequest += 1
    let request = f.collegesRequest
    f.loadingColleges = true
    let keep = Set(f.selected(1))
    let states = f.selected(0)
    Task {
      let items = await fetch("POST", "college/states/institute-list/", ["states": states])
      guard request == f.collegesRequest else { return }
      f.loadingColleges = false
      var seen = Set<String>()
      f.options[1] = items.filter { seen.insert($0.name).inserted }.map {
        $0.selected = keep.contains($0.name)
        return $0
      }
    }
  }
}
