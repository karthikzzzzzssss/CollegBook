import SwiftUI

/// Screens the Home tab pushes.
enum HomeRoute: Hashable {
  case choiceLists
  case feeDetails
  case ccms(id: Int, image: String?)
  case reels(startId: String)
}

private let navy = Color(hex: 0x131946)
private let cbNavy = Color(hex: 0x07183A)
private let cbTeal = Color(hex: 0x045356)

/// The Home tab: lib/features/home/home_page.dart, a port of the native
/// CollegeGuidanceFragment. Sizes are the native dp/sp values.
struct HomeView: View {
  let isSubscribed: Bool
  /// Native openCollegeTabWithPosition(): 0 Colleges, 1 CutOffs & Matchings, 2 Allotments.
  let openCutoffTab: (Int) -> Void
  let openMenu: () -> Void
  let openPackages: () -> Void
  /// The exam was switched: what other tabs loaded belongs to the old one.
  let onExamChanged: () -> Void

  static let contactNumber = "8500001406"

  @EnvironmentObject private var app: AppState
  @State private var data = HomeData()
  /// Until the first load finishes only the banner and the spinner show, so
  /// section titles never sit on screen without their content.
  @State private var firstLoadDone = false
  /// The page pushed over Home.
  @State private var pushed: HomeRoute?
  /// The banner has scrolled away (the pinned row turns green). A flag, not
  /// the scroll offset: state set on every scroll frame re-renders all of
  /// Home each frame and cancels a pull-to-refresh mid-request.
  @State private var collapsed = false
  @State private var sheet: DetailSheet?
  @State private var selectedExam: String?
  /// An exam switch is saving: the pill shows a spinner and can't be reopened.
  @State private var switchingExam = false
  /// The latest Home load: only its response is kept, so an older one that
  /// finishes last can't bring back the previous exam's data.
  @State private var loadToken = 0

  struct DetailSheet: Identifiable {
    let chip: String
    let title: String
    let description: String
    var id: String { title + chip }
  }

  var body: some View {
    CompatNavigationStack {
      GeometryReader { outer in
        let topInset = outer.safeAreaInsets.top
        ScrollViewReader { proxy in
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
              banner(topInset: topInset)
              if !firstLoadDone {
                ProgressView().tint(AppColors.primary).controlSize(.large)
                  .frame(maxWidth: .infinity).padding(.top, 160)
              } else {
                sections {
                  // Lands the green block right under the pinned bar on any
                  // iPhone: the marker sits above the section's 20pt white
                  // margin, and the scroll view runs up behind the status bar.
                  let anchor = UnitPoint(x: 0.5, y: (topInset + 46 - 20) / max(outer.size.height + topInset, 1))
                  withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("completeNeet", anchor: anchor) }
                }
                .padding(.bottom, 64)
              }
            }
          }
          .coordinateSpace(name: "homeScroll")
          .pullToRefresh { await refresh() }
        }
        .overlay(alignment: .top) { pinnedBar(topInset: topInset) }
        .ignoresSafeArea(edges: .top)
      }
      .background(Color.white)
      .hiddenNavigationBar()
      .compatDestination(item: $pushed) { route in
        switch route {
        case .feeDetails: GreenHeaderWebPage(title: "Fee Details", path: "college/fee/webview/")
        case .ccms(let id, let image): CcmsItemPage(itemId: id, imageURL: image)
        case .choiceLists: ChoiceListsEntry(isSubscribed: isSubscribed, openPackages: openPackages)
        case .reels(let startId): ReelsEntry(startId: startId, recommended: true)
        }
      }
      .sheet(item: $sheet) { DetailSheetView(sheet: $0) }
    }
    .task { await firstLoad() }
  }

  // MARK: Loading

  private func firstLoad() async {
    guard !firstLoadDone else { return }
    loadToken += 1
    let token = loadToken
    let loader = Task { await HomeData.load(app.api) }
    // Show what there is after 20s even if a request hangs.
    let timeout = Task {
      try? await Task.sleep(seconds: 20)
      firstLoadDone = true
    }
    let loaded = await loader.value
    timeout.cancel()
    if token == loadToken { data = loaded }
    firstLoadDone = true
  }

  private func refresh() async {
    loadToken += 1
    let token = loadToken
    let loaded = await HomeData.load(app.api, keeping: data)
    if token == loadToken { data = loaded }
  }

  private func selectExam(_ exam: ExamType) {
    guard exam.code != currentExam?.code, !switchingExam else { return }
    let previous = selectedExam
    selectedExam = exam.code
    switchingExam = true
    Task {
      defer { switchingExam = false }
      do {
        try await app.api.request("PATCH", "auth/exam-type/", body: ["exam_type": exam.code])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        app.show("Switched to \(exam.name)")
        onExamChanged()
        await refresh()
        // From here the server's answer decides, as on a fresh launch.
        if data.examTypes.contains(where: \.isSelected) { selectedExam = nil }
      } catch {
        // The server kept the old exam: show it again, not the one tapped.
        selectedExam = previous
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        app.show("Couldn't switch exam type, please try again")
      }
    }
  }

  private var currentExam: ExamType? {
    data.examTypes.first { $0.code == selectedExam } ?? data.examTypes.first { $0.isSelected } ?? data.examTypes.first
  }

  private func helpfulTool(_ title: String, showGuidance: @escaping () -> Void) {
    switch title {
    case "Cutoff": openCutoffTab(2)
    case "Closing Rank", "Matching": openCutoffTab(1)
    case "Colleges": openCutoffTab(0)
    case "1to1 counselor": showGuidance()
    case "ChoiceList": pushed = .choiceLists
    case "Fee Details": pushed = .feeDetails
    default: break
    }
  }

  // MARK: Banner

  /// AppBarLayout (250pt) + CollapsingToolbarLayout: the banner scrolls away
  /// with 0.7 parallax while the avatar row stays pinned.
  private func banner(topInset: CGFloat) -> some View {
    GeometryReader { geo in
      let minY = geo.frame(in: .named("homeScroll")).minY
      let pull = max(minY, 0)
      // Scrolling up moves the art at 70% speed; pulling down stretches it.
      let shift = minY < 0 ? -minY * 0.3 : -pull
      ZStack(alignment: .top) {
        Color.black
        Image("collegebook_home_banner").resizable().scaledToFill()
          .frame(width: geo.size.width, height: 250 + pull)
          .clipped()
        examPill
          .frame(maxWidth: .infinity)
          .padding(.top, 250 - 16 - 32 + pull)
      }
      .offset(y: shift)
      .onChangeCompat(of: -minY >= 250 - (topInset + 46)) { _, value in collapsed = value }
    }
    .frame(height: 250)
    .clipped()
  }

  /// conBannerTop: once the banner has scrolled away the pinned row turns
  /// brand green.
  private func pinnedBar(topInset: CGFloat) -> some View {
    HStack {
      Button(action: openMenu) {
        Image("ic_profile").renderingMode(.template).resizable()
          .foregroundStyle(Color(hex: 0x49454F)).padding(8)
          .frame(width: 36, height: 36)
          .background(.white, in: Circle())
      }
      .accessibilityLabel("Profile and menu")
      Spacer()
    }
    .padding(.horizontal, 16)
    // Just under the status bar, as on Android: no empty band above the
    // avatar once the bar turns green.
    .padding(.top, topInset)
    .padding(.bottom, 10)
    .background(collapsed ? AppColors.primary : .clear)
  }

  /// The yellow course spinner: the server's is_selected exam type, with a
  /// menu of the others.
  @ViewBuilder private var examPill: some View {
    if let current = currentExam {
      Menu {
        Section("Choose your exam") {
          ForEach(data.examTypes) { exam in
            Button {
              selectExam(exam)
            } label: {
              // The current exam carries a checkmark.
              if exam.code == current.code {
                Label(exam.name, systemImage: "checkmark")
              } else {
                Text(exam.name)
              }
            }
          }
        }
      } label: {
        HStack(spacing: 2) {
          Text(current.name).font(.inter(13, .bold)).padding(.horizontal, 8)
          ZStack {
            if switchingExam {
              ProgressView().tint(navy).scaleEffect(0.6)
            } else {
              Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
          }
          .frame(width: 14, height: 14)
        }
        .foregroundStyle(navy)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 32)
        .background(
          LinearGradient(
            colors: [Color(hex: 0xFFDF7D), Color(hex: 0xFDC24C), Color(hex: 0xF0981B)],
            startPoint: .top, endPoint: .bottom),
          in: Capsule())
        // A 44pt tall tap target around the 32pt pill, without moving it.
        .padding(.vertical, 6)
        .contentShape(Rectangle())
      }
      .padding(.vertical, -6)
      .disabled(switchingExam)
      .accessibilityLabel("Exam type, \(current.name)")
      .accessibilityHint(switchingExam ? "Switching" : "Opens the list of exams")
    } else {
      Color.clear.frame(height: 32)
    }
  }


  // MARK: Sections

  private func sections(showGuidance: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 0) {
    helpfulTools(showGuidance: showGuidance)
    newsUpdates
    webinars
    ccmsSection(match: "state", style: .state)
    liveEvents
    Color.clear.frame(height: 0).id("completeNeet")
    CompleteNeetView(recommended: data.recommended)
    ccmsSection(match: "cours", style: .course)
    ccmsSection(match: "sel", style: .counselling)
    ccmsSection(match: "countr", style: .state)
    HighlightsView()
    ReviewsView(reviews: data.guidance.objects("reviews").enumerated().map { Review(id: $0.offset, $0.element) }) {
      sheet = DetailSheet(chip: $0.meta, title: $0.name, description: $0.description)
    }
    FaqsView(faqs: data.guidance.objects("faqs"))
    }
  }

  /// HelpfulToolsAdapter: a 5-column grid of icons matched by title.
  @ViewBuilder
  private func helpfulTools(showGuidance: @escaping () -> Void) -> some View {
    if !data.helpTools.isEmpty {
      let rows = stride(from: 0, to: data.helpTools.count, by: 5).map {
        Array(data.helpTools[$0..<min($0 + 5, data.helpTools.count)])
      }
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          HStack(alignment: .top, spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, tool in
              toolButton(tool, showGuidance: showGuidance)
            }
            ForEach(row.count..<5, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
          }
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 16)
    }
  }

  private func toolButton(_ tool: JSONObject, showGuidance: @escaping () -> Void) -> some View {
    let title = tool.string("title") ?? ""
    return Button {
      helpfulTool(title, showGuidance: showGuidance)
    } label: {
      VStack(spacing: 7) {
        Image(Self.toolIcon(title)).renderingMode(.template).resizable()
          .foregroundStyle(.white).frame(width: 24, height: 24)
          .frame(width: 56, height: 56)
          .background(AppColors.primary, in: Circle())
        Text(title).font(.inter(9, .bold)).foregroundStyle(AppColors.primary)
          .multilineTextAlignment(.center).reservingLines(2, font: .inter(9, .bold))
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }

  static func toolIcon(_ title: String) -> String {
    switch title {
    case "Matching": "icon_matching"
    case "Fee Details": "icon_feedetails"
    case "Colleges": "icon_college"
    case "1to1 counselor": "icon_counselor"
    default: "icon_choicelist"
    }
  }

  private var newsUpdates: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionTitle("Catch up on the latest updates!").padding(.horizontal, 14)
      if !data.news.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 0) {
            ForEach(Array(data.news.enumerated()), id: \.offset) { _, item in
              Button {
                sheet = DetailSheet(
                  chip: item.string("updated_date") ?? "", title: item.string("title") ?? "",
                  description: item.string("description") ?? "")
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(item.string("updated_date") ?? "").font(.inter(10)).foregroundStyle(Color(hex: 0x8A8A9A))
                  Text(item.string("title") ?? "").font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x22226B))
                    .lineLimit(3).lineSpacing(2).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(width: 155, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .padding(4)
              }
              .buttonStyle(.plain)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 10)
        }
      }
    }
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(
        colors: [Color(hex: 0xD8D3F5), Color(hex: 0xF3D5E3), Color(hex: 0xFBE0D2)], startPoint: .leading,
        endPoint: .trailing),
      in: RoundedRectangle(cornerRadius: 16)
    )
    .padding(.horizontal, 14)
    .padding(.top, 14)
  }

  private var webinars: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionTitle("Webinars & Video Guides").padding(.horizontal, 16)
      if !data.reels.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 0) {
            ForEach(Array(data.reels.enumerated()), id: \.offset) { _, reel in
              Button {
                pushed = .reels(startId: reel.string("id") ?? "")
              } label: {
                NetImage(reel.string("thumbnail"))
                  .frame(width: 130, height: 180)
                  .background(Color(hex: 0xF7F2FA))
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .padding(4)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(reel.string("caption") ?? "Video")
            }
          }
          .padding(.horizontal, 10)
        }
      }
    }
    .padding(.top, 24)
  }

  // MARK: CCMS (States, Courses, Counselling, Countries)

  enum CcmsStyle {
    case course, counselling, state
    // CcmsCategoryItemAdapter.CardStyle: size, corner radius, gap.
    var size: CGFloat { self == .course ? 100 : self == .counselling ? 90 : 120 }
    var radius: CGFloat { self == .counselling ? 60 : 6 }
    var gap: CGFloat { self == .counselling ? 30 : 10 }
  }

  /// The native fetchCcmsCategories() matches category names by substring.
  @ViewBuilder
  private func ccmsSection(match: String, style: CcmsStyle) -> some View {
    if let category = data.ccms.first(where: { ($0.string("name") ?? "").lowercased().contains(match) }) {
      VStack(alignment: .leading, spacing: 8) {
        SectionTitle(category.string("name") ?? "").padding(.horizontal, 16)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: style.gap) {
            ForEach(Array(category.objects("items").enumerated()), id: \.offset) { _, item in
              Button {
                if let id = item.int("id") { pushed = .ccms(id: id, image: item["image"] as? String) }
              } label: {
                VStack(spacing: 4) {
                  NetImage(item["image"] as? String, placeholder: "home_iv_mirror")
                    .frame(width: style.size, height: style.size)
                    .clipShape(RoundedRectangle(cornerRadius: style.radius))
                  Text(item.string("title") ?? "").font(.inter(12, .bold)).foregroundStyle(.black)
                    .multilineTextAlignment(.center).lineLimit(2).frame(width: 80)
                }
                .frame(width: style.size)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 14)
        }
      }
      .padding(.top, 24)
    }
  }

  // MARK: Live events

  private var liveEvents: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionTitle("Live Events").padding(.horizontal, 16)
      if !data.events.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 0) {
            ForEach(Array(data.events.enumerated()), id: \.offset) { _, event in
              EventCard(event: event)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
        }
      }
    }
    .padding(.top, 24)
  }
}

// MARK: - Pieces

/// The 15pt Inter ExtraBold section titles.
struct SectionTitle: View {
  let text: String
  var color: Color = AppColors.primary
  init(_ text: String, color: Color = AppColors.primary) {
    self.text = text
    self.color = color
  }
  var body: some View {
    Text(text).font(.inter(15, .heavy)).foregroundStyle(color).lineLimit(1)
  }
}

/// ISO dates from the API (with or without fractional seconds).
enum APIDate {
  static func parse(_ string: String?) -> Date? {
    guard let string, !string.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: string) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: string) { return date }
    let plain = DateFormatter()
    plain.locale = Locale(identifier: "en_US_POSIX")
    for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
      plain.dateFormat = format
      if let date = plain.date(from: string) { return date }
    }
    return nil
  }
}

private struct EventCard: View {
  let event: JSONObject

  /// "hh:mm a dd MMM" of the start, then the end date's year.
  private var dateLine: String? {
    guard let start = APIDate.parse(event["startdate"] as? String),
      let end = APIDate.parse(event["enddate"] as? String)
    else { return nil }
    let format = DateFormatter()
    format.dateFormat = "hh:mm a dd MMM"
    return "\(format.string(from: start)) \(Calendar.current.component(.year, from: end))"
  }

  var body: some View {
    let end = APIDate.parse(event["enddate"] as? String)
    let expired = end.map { $0 < Date() } ?? false
    VStack(alignment: .leading, spacing: 0) {
      NetImage(event.string("image")).aspectRatio(16 / 9, contentMode: .fit).frame(maxWidth: .infinity).clipped()
      Text(event.string("title") ?? "").font(.inter(12, .semibold)).foregroundStyle(.black)
        .reservingLines(2, font: .inter(12, .semibold)).padding(.horizontal, 6).padding(.top, 8)
      if let dateLine {
        Text(dateLine).font(.inter(10, .semibold)).foregroundStyle(navy).padding(.horizontal, 6).padding(.top, 4)
      }
      if !expired, let fee = event.string("event_fee") {
        Text("Rs. \(fee)").font(.inter(13, .bold)).foregroundStyle(.black).padding(.horizontal, 6).padding(.top, 10)
      }
    }
    .padding(.horizontal, 4)
    .padding(.bottom, 12)
    .frame(width: 156, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(.white, in: RoundedRectangle(cornerRadius: 8))
    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
  }
}

/// bottom_sheet_news_detail: used for news items and full reviews.
private struct DetailSheetView: View {
  let sheet: HomeView.DetailSheet
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if !sheet.chip.isEmpty {
          Text(sheet.chip).font(.inter(12)).foregroundStyle(Color(hex: 0x2E2E7A))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(hex: 0xEEF0FB))
            .padding(.top, 20)
        }
        Text(sheet.title).font(.inter(19, .bold)).foregroundStyle(Color(hex: 0x1A1A2E)).padding(.top, 14)
        Rectangle().fill(Color(hex: 0xF0F0F0)).frame(height: 1).padding(.vertical, 16)
        Text(sheet.description).font(.inter(14)).foregroundStyle(Color(hex: 0x4A4A5A)).lineSpacing(6)
        Button {
          dismiss()
        } label: {
          Text("Close").font(.inter(15, .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(8)
            .background(Color(hex: 0x4F75EE), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.top, 24)
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 24)
    }
    .sheetDetents([.medium, .large])
    .sheetDragIndicatorVisible()
    .sheetCornerRadius(20)
  }
}

// MARK: - Explore Admission Guidance (green block)

private struct CompleteNeetView: View {
  let recommended: [JSONObject]

  static let guidance = [
    ("Low Budget MD/MS Admissions", "Private Colleges I Deemed Universities"),
    ("Management NRI/IP Quota Admissions", "Private Colleges I Deemed Universities"),
    ("NEET PG Counselling Assistance", "All India I State I Private College I Deemed Universities"),
  ]

  static let specialities = [
    "Radiodiagnosis", "Dermatology", "General Medicine", "Obstetrics and Gynaecology (OBG)", "General Surgery",
    "Paediatrics", "Orthopaedics", "Ophthalmology", "ENT", "Anaesthesiology", "Psychiatry", "Respiratory Medicine",
    "Pathology", "Community Medicine (PSM)", "Microbiology", "Anatomy", "Biochemistry", "Forensic Medicine (FMT)",
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        SectionTitle("Explore Admission Guidance", color: .white)
        Spacer(minLength: 0)
        Button {
          Platform.call(HomeView.contactNumber)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "phone.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0x49454F))
            Text(HomeView.contactNumber).font(.inter(11.5, .semibold)).foregroundStyle(navy)
          }
          .padding(.horizontal, 10)
          .frame(height: 28)
          .background(Color(hex: 0xFFC812), in: Capsule())
        }
        .accessibilityLabel("Contact Us \(HomeView.contactNumber)")
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          ForEach(Self.guidance, id: \.0) { title, description in
            VStack(spacing: 0) {
              Text(title).font(.inter(15, .heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
              Rectangle().fill(AppColors.navLabel).frame(height: 2).padding(.horizontal, 20).padding(.top, 6)
              Text(description).font(.inter(10)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.top, 6)
              Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 16, leading: 14, bottom: 10, trailing: 14))
            .frame(width: 140, height: 150)
            .background(Color(hex: 0x136105), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppColors.allIndia, lineWidth: 0.5))
            .clipped()
            .padding(4)
          }
        }
        .padding(.horizontal, 10)
      }
      .padding(.top, 14)

      FlowStack(spacing: 8, lineSpacing: 8) {
        ForEach(Self.specialities, id: \.self) { speciality in
          Text(speciality).font(.inter(12, .medium)).foregroundStyle(AppColors.primary).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(AppColors.allIndia, in: Capsule())
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)

      if !recommended.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          SectionTitle("Recommended Colleges", color: .white).padding(.leading, 16)
          RecommendedGrid(colleges: recommended)
        }
        .padding(.horizontal, 4)
        .padding(.top, 24)
      }
    }
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(GreenHeader.gradient)
    .padding(.top, 20)
    // One look on every iPhone: fixed-size cards and the title row break at
    // other Text Size settings.
    .dynamicTypeSize(.medium)
  }
}

/// GridLayoutManager(3 rows, HORIZONTAL): colleges fill each column top to
/// bottom, then the next column.
private struct RecommendedGrid: View {
  let colleges: [JSONObject]

  var body: some View {
    let columns = stride(from: 0, to: colleges.count, by: 3).map { Array(colleges[$0..<min($0 + 3, colleges.count)]) }
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 0) {
        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
          VStack(spacing: 0) {
            ForEach(Array(column.enumerated()), id: \.offset) { _, college in card(college) }
          }
        }
      }
      .padding(.horizontal, 8)
    }
  }

  private func card(_ college: JSONObject) -> some View {
    let city = college.string("city") ?? ""
    let state = college.string("state") ?? ""
    return HStack(alignment: .top, spacing: 10) {
      NetImage(college["image"] as? String, placeholder: "home_iv_rank_image")
        .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 4))
      VStack(alignment: .leading, spacing: 4) {
        Text(college.string("name") ?? "").font(.inter(14, .semibold)).lineLimit(2)
        Text(city.isEmpty ? state : "\(city), \(state)").font(.inter(14, .medium)).lineLimit(1)
      }
      .foregroundStyle(AppColors.primary)
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(width: 327, height: 84, alignment: .topLeading)
    .background(
      // On the card only: on the whole view it also falls behind the text.
      RoundedRectangle(cornerRadius: 8).fill(AppColors.allIndia).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    )
    .padding(4)
  }
}

// MARK: - Why CollegeBook (layout_collegebook_highlights)

private struct HighlightsView: View {
  static let features = [
    ("home_img_cb_feat_department", "Real Department\nInformation", "Know HOD, faculty, clinical exposure, hands-on & work culture"),
    ("home_img_cb_feat_mentors", "Current PGs &\nFaculty Mentors", "Talk to current PGs and faculty from inside the college"),
    ("home_img_cb_feat_fees", "Complete Fee\nDetails", "All fees including tuition, hostel, exam and hidden charges"),
    ("home_img_cb_feat_cutoffs", "Real-Time Cutoffs\n& Allotments", "Latest updates, trends and analysis"),
    ("home_img_cb_feat_events", "Pre-PG Events\nby Department", "What to study, must-know topics, tips from current PGs"),
    ("home_img_cb_feat_support", "End-to-End\nAdmission Support", "From registration to allotment and even after joining"),
  ]

  var body: some View {
    VStack(spacing: 0) {
      hero.padding(.bottom, -24)
      HStack(spacing: 0) {
        // The colleges stat keeps its natural width; the doctors stat takes
        // the rest. (Competing priorities squeezed one to zero width, and its
        // text then wrapped a letter per line into a very tall empty card.)
        stat("home_img_cb_stat_colleges", "2000+", "Colleges &\nInstitutes").fixedSize()
        Rectangle().fill(Color(hex: 0xC3DBDB)).frame(width: 1, height: 44).padding(.horizontal, 12)
        stat("home_img_cb_stat_doctors", "500K+", "Doctors’ Community\n(PGs, Faculty, Alumni)")
      }
      .padding(10)
      .background(.white, in: RoundedRectangle(cornerRadius: 18))
      .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
      .padding(.horizontal, 12)

      VStack(spacing: 7) {
        featureRow(Array(Self.features[0..<3]))
        featureRow(Array(Self.features[3...]))
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
    }
    .padding(.bottom, 16)
    .background(
      LinearGradient(
        colors: [Color(hex: 0xE6FDFC), Color(hex: 0xF7FEFC), Color(hex: 0xEEF9F8)], startPoint: .top, endPoint: .bottom)
    )
    .padding(.top, 16)
  }

  private var hero: some View {
    GeometryReader { geo in
      let width = geo.size.width
      ZStack(alignment: .topLeading) {
        Image("home_img_cb_doctor").resizable().scaledToFit()
          .frame(width: width * 0.445)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.top, 2)
        VStack(alignment: .leading, spacing: 0) {
          Image("home_img_cb_logo_why").resizable().scaledToFit().frame(width: width * 0.62)
            .padding(.leading, 18).padding(.top, 10)
            .accessibilityLabel("Why CollegeBook, by the doctor for the doctor")
          Text("Talk to Current").font(.inter(21, .heavy)).foregroundStyle(cbNavy)
            .padding(.leading, 22).padding(.top, 16)
          HStack(spacing: 6) {
            Text(" PGs & Faculty").font(.inter(21, .heavy)).foregroundStyle(cbTeal)
            Image("home_img_cb_spark").resizable().scaledToFit().frame(width: 14)
          }
          .padding(.leading, 22)
          Text("Get Real Insights from\nInside the College.").font(.inter(13.5, .medium)).foregroundStyle(.black)
            .lineSpacing(3).padding(.leading, 22).padding(.top, 6)
          HStack(spacing: 10) {
            Image(systemName: "phone.fill").font(.system(size: 14)).foregroundStyle(.white)
            Text("Explore Mentors").font(.inter(12.5, .medium)).foregroundStyle(.white)
            Image("ic_cb_chevron_right").resizable().frame(width: 16, height: 16)
          }
          .padding(.horizontal, 12).padding(.vertical, 9)
          .background(cbTeal, in: Capsule())
          .padding(.leading, 18).padding(.top, 10)
        }
      }
    }
    // img_cb_doctor is 419x586 at 44.5% of the width, 2pt from the top.
    .aspectRatio(1 / (2 / 402 + 0.445 * 586 / 419), contentMode: .fit)
  }

  private func stat(_ image: String, _ number: String, _ label: String) -> some View {
    HStack(spacing: 8) {
      Image(image).resizable().frame(width: 48, height: 48).clipShape(Circle())
      VStack(alignment: .leading, spacing: 0) {
        Text(number).font(.inter(18, .heavy)).foregroundStyle(Color(hex: 0x023E42))
        Text(label).font(.inter(10.5, .medium)).foregroundStyle(Color(hex: 0x626376)).lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private func featureRow(_ features: [(String, String, String)]) -> some View {
    HStack(alignment: .top, spacing: 6) {
      ForEach(features, id: \.0) { image, title, description in
        VStack(alignment: .leading, spacing: 0) {
          Image(image).resizable().frame(width: 44, height: 44)
          Text(title).font(.inter(12, .bold)).foregroundStyle(cbNavy).lineSpacing(2).padding(.top, 6)
            .fixedSize(horizontal: false, vertical: true)
          Text(description).font(.inter(10)).foregroundStyle(Color(hex: 0x6A6C7F)).lineSpacing(3).padding(.top, 5)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 6, leading: 10, bottom: 8, trailing: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xEDF4F3)))
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Real Experiences (reviews)

private struct ReviewsView: View {
  let reviews: [Review]
  let open: (Review) -> Void

  @State private var page: Int? = 0

  /// PagerSnapHelper: a fling settles on one card at a time (iOS 17); before,
  /// the cards scroll freely and the dots follow the one nearest the start.
  @ViewBuilder private func cards(cardWidth: CGFloat) -> some View {
    if #available(iOS 17, *), !Compat.legacy {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(reviews) { review in
            ReviewCard(review: review, width: cardWidth).onTapGesture { open(review) }.id(review.id)
          }
        }
        .scrollTargetLayout()
        .fixedSize(horizontal: false, vertical: true)
      }
      .contentMargins(.horizontal, 18, for: .scrollContent)
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: $page, anchor: .leading)
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(reviews) { review in
            ReviewCard(review: review, width: cardWidth).onTapGesture { open(review) }
              .background(
                GeometryReader { g in
                  Color.clear.preference(key: CardStarts.self, value: [review.id: g.frame(in: .named("reviews")).minX])
                })
          }
        }
        .padding(.horizontal, 18)
        .fixedSize(horizontal: false, vertical: true)
      }
      .coordinateSpace(name: "reviews")
      .onPreferenceChange(CardStarts.self) { starts in
        page = starts.min { abs($0.value - 18) < abs($1.value - 18) }?.key
      }
    }
  }

  private struct CardStarts: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
      value.merge(nextValue()) { $1 }
    }
  }

  var body: some View {
    if !reviews.isEmpty {
      let cardWidth = (UIScreen.main.bounds.width * 0.8).rounded()
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Real Experiences").font(.inter(15, .bold)).foregroundStyle(AppColors.primary)
          Text("See how CollegeBook helped students make better decisions.").font(.inter(12, .medium))
            .foregroundStyle(Color(hex: 0x7C8094))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 20)

        cards(cardWidth: cardWidth).padding(.top, 16)

        if reviews.count > 1 {
          HStack(spacing: 10) {
            ForEach(reviews) { review in
              Circle().fill(review.id == (page ?? 0) ? Color(hex: 0x045B52) : Color(hex: 0xE3E5E8))
                .frame(width: 8, height: 8)
            }
          }
          .padding(.top, 14)
        }
      }
    }
  }
}

private struct ReviewCard: View {
  let review: Review
  let width: CGFloat

  private static let quoteFont = UIFont(name: "Inter-Regular", size: 14) ?? .systemFont(ofSize: 14)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        NetImage(review.image, placeholder: "home_iv_user_profile")
          .frame(width: 65, height: 65)
          .background(Color(hex: 0xEEF2F4))
          .clipShape(Circle())
        VStack(alignment: .leading, spacing: 1) {
          Text(review.name).font(.inter(15, .bold)).foregroundStyle(cbNavy).lineLimit(1).padding(.trailing, 32)
          if !review.meta.isEmpty {
            Text(review.meta).font(.inter(12)).foregroundStyle(Color(hex: 0x6F748A)).lineLimit(1)
          }
          HStack(spacing: 5) {
            Image("ic_review_verified").resizable().frame(width: 16, height: 16)
            Text("Verified User").font(.inter(12, .medium)).foregroundStyle(Color(hex: 0x13706B))
          }
        }
        .padding(.top, 4)
        Spacer(minLength: 0)
        Image("home_img_review_quote").resizable().scaledToFit().frame(width: 26)
      }
      Text(readMore(width: width - 24))
        .font(.inter(14))
        .foregroundStyle(Color(hex: 0x3B4256))
        .lineSpacing(6)
        .reservingLines(3, font: .inter(14), lineSpacing: 6)
      HStack(spacing: 3) {
        ForEach(0..<review.stars, id: \.self) { _ in
          Image("ic_review_star").resizable().frame(width: 16, height: 16)
        }
      }
    }
    .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
    .frame(width: width, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(.white, in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xEDF1F0)))
    .contentShape(Rectangle())
    .accessibilityAddTraits(.isButton)
  }

  /// InlineReadMore.build(): text over three lines is cut as
  /// "... Read More" (bold, #0B6965).
  private func readMore(width: CGFloat) -> AttributedString {
    let text = review.description.isEmpty ? "" : "“\(review.description)”"
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 6
    let attrs: [NSAttributedString.Key: Any] = [.font: Self.quoteFont, .paragraphStyle: paragraph]
    func lines(_ s: String) -> Int {
      let height = (s as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin],
        attributes: attrs, context: nil
      ).height
      return Int((height + 6) / (Self.quoteFont.lineHeight + 6) + 0.01)
    }
    var more = AttributedString("Read More")
    more.font = .inter(14, .bold)
    more.foregroundColor = Color(hex: 0x0B6965)
    if lines(text) <= 3 { return AttributedString(text) }
    // Binary search for the longest prefix that fits with the suffix.
    var low = 0
    var high = text.count
    while low < high {
      let mid = (low + high + 1) / 2
      let candidate = String(text.prefix(mid)).trimmingCharacters(in: .whitespaces) + "... Read More"
      if lines(candidate) <= 3 { low = mid } else { high = mid - 1 }
    }
    return AttributedString(String(text.prefix(low)).trimmingCharacters(in: .whitespaces) + "... ") + more
  }
}

// MARK: - FAQs

private struct FaqsView: View {
  let faqs: [JSONObject]

  var body: some View {
    if !faqs.isEmpty {
      VStack(alignment: .leading, spacing: 16) {
        Text("Frequently asked questions").font(.inter(15, .bold)).foregroundStyle(AppColors.primary)
          .padding(.horizontal, 20)
        VStack(spacing: 0) {
          ForEach(Array(faqs.enumerated()), id: \.offset) { _, faq in FaqRow(faq: faq) }
        }
        .padding(.horizontal, 18)
      }
      .padding(.top, 20)
    }
  }
}

private struct FaqRow: View {
  let faq: JSONObject
  @State private var open = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Button {
        open.toggle()
      } label: {
        HStack {
          Text(faq.string("title") ?? "").font(.inter(15, .bold)).foregroundStyle(.black)
            .multilineTextAlignment(.leading)
          Spacer(minLength: 8)
          Image(systemName: "plus").font(.system(size: 18)).foregroundStyle(Color(hex: 0x1A1A1A))
        }
        .padding(.leading, 12).padding(.trailing, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(open ? .isSelected : [])
      if open {
        Text(faq.string("description") ?? "").font(.inter(14)).foregroundStyle(.black)
          .padding(.leading, 12).padding(.trailing, 6)
      }
    }
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 4))
    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xE6E6E6)))
    .padding(3)
  }
}

// MARK: - Flow layout

/// A Wrap: children left to right, wrapping onto new lines (FlowStack picks
/// it where Layout exists).
@available(iOS 16, *)
struct FlowLayout: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    var widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        y += lineHeight + lineSpacing
        x = 0
        lineHeight = 0
      }
      x += size.width + spacing
      widest = max(widest, x - spacing)
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var lineHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        y += lineHeight + lineSpacing
        x = bounds.minX
        lineHeight = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}
