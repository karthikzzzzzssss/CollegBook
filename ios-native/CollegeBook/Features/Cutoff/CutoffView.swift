import SwiftUI

/// The Cutoff tab: lib/features/cutoff/cutoff_page.dart, a port of the native
/// CollegehomeTabsFragment with its three pages: Colleges, CutOffs &
/// Matchings and Allotments, plus the Filters sheet.
struct CutoffView: View {
  let isSubscribed: Bool
  @Binding var selectedTab: Int
  let openMentor: () -> Void
  let openPremium: () -> Void
  let openPackages: () -> Void

  @EnvironmentObject private var app: AppState
  @StateObject private var filters = CutoffFilterState(api: .shared)
  @State private var filtersLoaded = false
  /// mapParams: only the counselling type, used by the header toggle — so
  /// switching AIC/SC there drops the applied filters, as natively.
  @State private var mapParams = ["councelling_type": "AIC"]
  /// filtermapParams: kept across Applies; each Apply builds on the last.
  @State private var filterParams: [String: String] = [:]
  /// The params the pages are showing.
  @State private var params = ["councelling_type": "AIC"]
  /// Bumped whenever the pages must be recreated with new params.
  @State private var generation = 0
  @State private var visited: Set<Int> = []
  @State private var showFilters = false
  /// The college details page pushed over the tab.
  @State private var details: CollegeDetailsRoute?

  static let tabs = ["Colleges", "CutOffs & Matchings", "Allotments"]

  var body: some View {
    CompatNavigationStack {
      VStack(spacing: 0) {
        header
        ZStack {
          ForEach(0..<3, id: \.self) { index in
            if visited.contains(index) {
              page(index)
                // Also on a subscription change: pages were fetched at the free limit.
                .id("\(index)-\(generation)-\(isSubscribed)")
                .opacity(index == selectedTab ? 1 : 0)
                .allowsHitTesting(index == selectedTab)
                .accessibilityHidden(index != selectedTab)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(stateGreen.ignoresSafeArea(edges: .top))
      .hiddenNavigationBar()
      .compatDestination(item: $details) { CollegeDetailsPage(route: $0) }
      .sheet(isPresented: $showFilters) {
        CutoffFilterSheet(
          filters: filters, isSubscribed: isSubscribed, currentParams: filterParams,
          onApply: applyFilters,
          onGoPremium: {
            showFilters = false
            openPackages()
          })
      }
    }
    .onAppear {
      if !filtersLoaded {
        filtersLoaded = true
        Task { await filters.loadHomeFilters() }
      }
      visited.insert(selectedTab)
    }
    .onChangeCompat(of: selectedTab) { _, tab in visited.insert(tab) }
  }

  @ViewBuilder
  private func page(_ index: Int) -> some View {
    if index == 0 {
      CollegesPage(
        params: params.merging(["query": "institute"]) { $1 }, isSubscribed: isSubscribed,
        openMentor: openMentor, openPremium: openPremium,
        openDetails: { details = $0 },
        onDefaultState: { filters.setDefaultState($0, counselling: $1) })
    } else {
      WebListPage(
        path: index == 1 ? "college/rank-matching/webview/" : "college/allotment/webview/",
        errorText: index == 1 ? "Couldn't load cutoffs and matchings." : "Couldn't load allotments.",
        params: params, isSubscribed: isSubscribed, openPremium: openPremium)
    }
  }

  private func setCounselling(_ type: String) {
    filters.counselling = type
    mapParams["councelling_type"] = type
    params = mapParams
    recreatePages()
  }

  private func applyFilters(_ applied: [String: String]) {
    filterParams = applied
    params = applied
    recreatePages()
  }

  private func recreatePages() {
    generation += 1
    visited = [selectedTab]
    Task { await filters.loadHomeFilters() }
  }

  // MARK: Header

  private var header: some View {
    let type = params["councelling_type"] ?? "AIC"
    return VStack(spacing: 8) {
      HStack(spacing: 8) {
        HStack(spacing: 0) {
          toggle("All India Counselling", selected: type == "AIC") { setCounselling("AIC") }
          toggle("State Counselling", selected: type == "SC") { setCounselling("SC") }
        }
        .padding(3)
        .background(track)

        Button {
          showFilters = true
        } label: {
          HStack(spacing: 6) {
            Image("ic_baseline_filter").renderingMode(.template).resizable().frame(width: 18, height: 18)
            Text("Filter").font(.inter(13, .bold))
          }
          .foregroundStyle(AppColors.allIndia)
          .padding(.leading, 10).padding(.trailing, 12)
          .frame(maxHeight: .infinity)
          .background(track)
        }
        .buttonStyle(.plain)
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 16)
      .padding(.top, 12)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          ForEach(Array(Self.tabs.enumerated()), id: \.offset) { index, label in
            subTab(index, label)
          }
        }
        // tabContentStart 19dp less the first tab's 12dp padding.
        .padding(.leading, 7)
      }
      .frame(height: 44)
    }
    .background(stateGreen)
  }

  /// A TabLayout tab (cutoff_page.dart _Tab): 12pt side padding, Inter Bold
  /// 13, a 3pt all_india indicator as wide as the text.
  private func subTab(_ index: Int, _ label: String) -> some View {
    Button {
      selectedTab = index
    } label: {
      Text(label).font(.inter(13, .bold))
        .foregroundStyle(index == selectedTab ? .white : .white.opacity(0.65))
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          if index == selectedTab {
            RoundedCornersShape(topLeadingRadius: 3, topTrailingRadius: 3).fill(AppColors.allIndia)
              .frame(height: 3)
          }
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(index == selectedTab ? .isSelected : [])
  }

  private var track: some View {
    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25)))
  }

  private func toggle(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).font(.inter(12, .bold)).lineLimit(1).minimumScaleFactor(0.83)
        .foregroundStyle(selected ? stateGreen : .white)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(selected ? AppColors.allIndia : .clear, in: RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

// MARK: - Colleges page (CollegesFragment)

struct CollegeDetailsRoute: Hashable {
  let collegeId: String
  let counselling: String
}

private struct CollegesPage: View {
  let params: [String: String]
  let isSubscribed: Bool
  let openMentor: () -> Void
  let openPremium: () -> Void
  let openDetails: (CollegeDetailsRoute) -> Void
  let onDefaultState: (String?, String?) -> Void

  @EnvironmentObject private var app: AppState
  @State private var colleges: [JSONObject] = []
  @State private var currentParams: [String: String] = [:]
  @State private var page = 1
  @State private var totalPages = 1
  @State private var request = 0
  @State private var examRank = 0
  @State private var counselling = "AIC"
  @State private var filterBy = ""
  @State private var loading = false
  @State private var loaded = false
  @State private var askRank = false
  @State private var rankText = ""
  @State private var cutoffSheet: CutoffSheetItem?

  struct CutoffSheetItem: Identifiable {
    let college: JSONObject
    var id: String { college.string("id") ?? "" }
  }

  /// Subscribers page through every college (30 a page); free users see 3
  /// and the Go Premium footer.
  private var limit: Int { isSubscribed ? 30 : 3 }

  var body: some View {
    ZStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(filterBy).font(.inter(11)).foregroundStyle(.white).padding(.leading, 19).padding(.top, 10)
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(colleges.enumerated()), id: \.offset) { index, college in
              CollegeCard(
                college: college, examRank: examRank, isSubscribed: isSubscribed,
                onOpen: { showDetails(college) },
                onCutoffRow: {
                  if examRank == 0 {
                    rankText = ""
                    askRank = true
                  } else {
                    showDetails(college)
                  }
                },
                onMore: {
                  if isSubscribed { cutoffSheet = CutoffSheetItem(college: college) } else {
                    app.show("Subscribe to unlock more cutoffs")
                  }
                },
                onCall: openMentor
              )
              .onAppear {
                // Next page a few cards before the end, so a fling never waits.
                if index >= colleges.count - 4 { loadMore() }
              }
            }
            footer
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 80)
        }
        .pullToRefresh { await load(currentParams, page: 1) }
      }

      if loaded, !loading, colleges.isEmpty {
        Text("We couldn’t find any colleges matching your search.").font(.inter(18, .bold)).foregroundStyle(.white)
          .multilineTextAlignment(.center).padding(.horizontal, 16)
      }
      if loading, colleges.isEmpty {
        ProgressView().tint(AppColors.allIndia).controlSize(.large)
      }
    }
    .background(stateGreen)
    .task {
      guard !loaded, !loading else { return }
      await load(params, page: 1)
    }
    .compatTextAlert(
      "Rank", isPresented: $askRank, fields: [CompatAlertField(placeholder: "Enter your rank", text: $rankText)],
      confirm: "Ok"
    ) {
      let rank = String(rankText.filter(\.isNumber).prefix(9))
      guard !rank.isEmpty, rank.first != "0" else {
        app.show("Please enter your Rank")
        return
      }
      Task { await load(["councelling_type": counselling, "query": "institute", "rank": rank], page: 1) }
    }
    .sheet(item: $cutoffSheet) { item in
      CutoffSheet(college: item.college, counselling: counselling, isSubscribed: isSubscribed) {
        cutoffSheet = nil
        openPremium()
      }
    }
  }

  @ViewBuilder private var footer: some View {
    let loadingMore = loading && !colleges.isEmpty
    if loadingMore || (!isSubscribed && !colleges.isEmpty) {
      VStack(spacing: 16) {
        if loadingMore { ProgressView().tint(AppColors.allIndia) }
        if !isSubscribed && !colleges.isEmpty && !loadingMore {
          PremiumPrompt(textColor: .white, buttonColor: Color(hex: 0xFFC812), buttonTextColor: .black, action: openPremium)
            .padding(.top, 16)
        }
      }
      .padding(.vertical, 16)
    }
  }

  private func showDetails(_ college: JSONObject) {
    openDetails(CollegeDetailsRoute(collegeId: college.string("id") ?? "", counselling: counselling))
  }

  private func loadMore() {
    guard isSubscribed, !loading, page < totalPages else { return }
    // Set here, not in the Task: another card can appear before the Task runs.
    loading = true
    Task { await load(currentParams, page: page + 1) }
  }

  private func load(_ params: [String: String], page target: Int) async {
    let fresh = target == 1
    if fresh {
      request += 1
      currentParams = params
    }
    let current = request
    loading = true
    defer {
      if current == request {
        loading = false
        loaded = true
      }
    }
    do {
      var query = params
      query["page"] = "\(target)"
      query["limit"] = "\(limit)"
      let data = try await app.api.object("college/homepage", query: query)
      guard current == request else { return }
      let results = data.objects("results")
      page = target
      totalPages = data.int("total_page") ?? 1
      if fresh {
        applyDefaultParameter(data.object("default_parameter"))
        colleges = results
      } else {
        colleges += results
      }
    } catch {
      // A page recreated mid-request cancels it: nothing failed.
      guard current == request, !Task.isCancelled else { return }
      app.show(fresh ? "Couldn't load colleges. Check your internet and try again." : "Couldn't load more colleges")
    }
  }

  private func applyDefaultParameter(_ value: JSONObject?) {
    guard let value else { return }
    examRank = value.int("rank") ?? 0
    counselling = value["councelling_type"] as? String ?? counselling
    let state = value["state"] as? String
    let category = value.string("category") ?? ""
    onDefaultState(state, value["councelling_type"] as? String)
    if counselling == "AIC" {
      filterBy = "Filter By: AIC/\(category)"
    } else if let state, !state.isEmpty {
      filterBy = "Filter By: \(state)/\(category)"
    } else {
      filterBy = "Filter By: \(category)"
    }
  }
}

/// "To Unlock Cutoff & Matching" + "Go Premium".
struct PremiumPrompt: View {
  let textColor: Color
  let buttonColor: Color
  let buttonTextColor: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Text("To Unlock Cutoff & Matching").font(.inter(15)).foregroundStyle(textColor)
        Text("Go Premium").font(.inter(15, .bold)).foregroundStyle(buttonTextColor)
          .padding(.horizontal, 14).padding(.vertical, 5)
          .background(buttonColor, in: RoundedRectangle(cornerRadius: 6))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 0.5))
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// row_rankwise_colleges.xml.
private struct CollegeCard: View {
  let college: JSONObject
  let examRank: Int
  let isSubscribed: Bool
  let onOpen: () -> Void
  let onCutoffRow: () -> Void
  let onMore: () -> Void
  let onCall: () -> Void

  var body: some View {
    let cutoffs = college.objects("cutoff")
    Button(action: onOpen) {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          Image("home_iv_rank_image").resizable().scaledToFill().frame(width: 55, height: 55)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.leading, 12).padding(.top, 6)
          VStack(alignment: .leading, spacing: 4) {
            Text(college.string("name") ?? "").font(.inter(14, .semibold)).foregroundStyle(stateGreen)
              .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
              Image("location_on").renderingMode(.template).resizable().frame(width: 14, height: 14)
              // The native adapter never sets this view, so every card shows
              // the layout's placeholder.
              Text("Patancheruvu Hyderabad ").font(.inter(12, .medium))
            }
            .foregroundStyle(stateGreen)
          }
          .padding(10)
          Spacer(minLength: 0)
        }

        HStack(spacing: 0) {
          stat("currency_rupee_circle_24px", college.string("course_fee"), "Tuition Fees")
          statDivider
          stat("ic_bond_year", college.string("bond_year"), "Bond Year")
          statDivider
          stat("ic_bond_penalty", college.string("bond_penalty"), "Bond Penalty")
          statDivider
          stat("currency_rupee_circle_24px", college.string("stipend"), "Stipend")
        }
        .padding(.vertical, 10)
        .background(Color(hex: 0xF5F7FB), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xF5F5F5), lineWidth: 0.5))
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 0, trailing: 10))

        CutoffTable(cutoffs: cutoffs, examRank: examRank, onRow: onCutoffRow).padding(.top, 10)

        HStack(spacing: 12) {
          if !cutoffs.isEmpty {
            cardButton(isSubscribed ? "ic_baseline_lock_open_24" : "ic_baseline_lock_24", "See more CutOFF", .medium, onMore)
          }
          cardButton("phone_in_talk", "Call Counsellor", .bold, onCall)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
      }
      .padding(.bottom, 10)
      .background(.white, in: RoundedRectangle(cornerRadius: 12))
      .shadow(color: .black.opacity(0.2), radius: 3, y: 1.5)
      .padding(.horizontal, 6.5)
      .padding(.vertical, 8)
    }
    .buttonStyle(.plain)
  }

  private var statDivider: some View { Rectangle().fill(Color(hex: 0xDDDDDD)).frame(width: 1, height: 30) }

  private func stat(_ icon: String, _ value: String?, _ label: String) -> some View {
    HStack(alignment: .top, spacing: 4) {
      Image(icon).renderingMode(.template).resizable().frame(width: 14, height: 16).foregroundStyle(grey666)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 0) {
        Text(value ?? "").font(.inter(12, .bold)).foregroundStyle(.black).lineLimit(1).fixedSize()
        Text(label).font(.inter(9)).foregroundStyle(grey666).lineLimit(1).fixedSize()
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func cardButton(_ icon: String, _ label: String, _ weight: Font.Weight, _ action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(icon).renderingMode(.template).resizable().frame(width: 16, height: 16)
        Text(label).font(.inter(13, weight)).lineLimit(1)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity).frame(height: 36)
      .background(stateGreen, in: RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }
}

/// The card's horizontally scrolling cutoff table (headerRow + at most two
/// CutoffMarksAdapter rows).
private struct CutoffTable: View {
  let cutoffs: [JSONObject]
  let examRank: Int
  let onRow: () -> Void

  var body: some View {
    let rows = Array(cutoffs.prefix(cutoffs.count == 1 ? 1 : 2))
    ScrollView(.horizontal, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          Text("CutOff(2024)").font(.inter(12, .medium)).foregroundStyle(.black).frame(width: 100, alignment: .leading)
          ForEach([("R1", false), ("R2", false), ("R3", true), ("R4", true), ("R5", true), ("Fee", true), ("Matching", true)], id: \.0) {
            label, muted in
            Text(label).font(.inter(12)).foregroundStyle(muted ? grey47 : .black).frame(width: 60)
          }
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)

        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            Button(action: onRow) {
              HStack(spacing: 4) {
                Text(row.string("course_name") ?? "").font(.inter(12)).foregroundStyle(.black)
                  .frame(width: 100, alignment: .leading).multilineTextAlignment(.leading)
                ForEach(["round_1", "round_2", "round_3", "round_4", "round_5"], id: \.self) { key in
                  Text(row.string(key) ?? "N/A").font(.inter(12, .bold)).foregroundStyle(.black).frame(width: 60)
                }
                Text(row.string("fee") ?? "").font(.inter(12, .bold)).foregroundStyle(.black).frame(width: 65)
                if examRank != 0 {
                  Image(row.bool("is_match") == true ? "ic_baseline_rank_match" : "ic_baseline_rank_unamtch")
                    .renderingMode(.template).resizable().frame(width: 18, height: 18)
                    .foregroundStyle(Color(hex: 0x404040)).padding(.leading, 16)
                } else {
                  Text("Enter Rank").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x0178D4))
                    .frame(width: 60).padding(.leading, 4)
                }
              }
              .padding(.leading, 4)
              .padding(.top, 8).padding(.bottom, 10)
              .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xEFEEEE)).frame(height: 1) }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 10)
      }
    }
  }
}

/// college_hompage_bottomsheet_rankcard.xml: 70% of the screen, the
/// server-rendered college/cutoff/{id}/webview/ page inside.
private struct CutoffSheet: View {
  let college: JSONObject
  let counselling: String
  let isSubscribed: Bool
  let onGoPremium: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        Text(college.string("name") ?? "").font(.inter(23, .bold)).foregroundStyle(grey47)
        Spacer(minLength: 0)
        Button {
          dismiss()
        } label: {
          Image("cutoff_mentor_closed").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(.black)
        }
        .accessibilityLabel("Close")
      }
      .padding(EdgeInsets(top: 17, leading: 21, bottom: 0, trailing: 16))
      Text("NEET PG - \(college.string("cutoff_and_course_count") ?? "")").font(.inter(15)).foregroundStyle(grey47)
        .padding(EdgeInsets(top: 4, leading: 21, bottom: 12, trailing: 16))
      AuthWebView(
        url: APIClient.shared.url(
          "college/cutoff/\(college.string("id") ?? "")/webview/", query: ["councelling_type": counselling]))
      if !isSubscribed {
        PremiumPrompt(textColor: grey47, buttonColor: Color(hex: 0x0178D4), buttonTextColor: .white, action: onGoPremium)
          .padding(.vertical, 10)
      }
    }
    .background(.white)
    .sheetDetents([.fraction(0.7)])
    .sheetCornerRadius(18)
    .interactiveDismissDisabled()
  }
}

/// CollegeDetailsWebviewActivity: college/full-details/{id}/webview/.
struct CollegeDetailsPage: View {
  let route: CollegeDetailsRoute
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 22, height: 22)
            .foregroundStyle(.white)
            .extendedTapArea(horizontal: 11, vertical: 11)
        }
        .accessibilityLabel("Back")
        Text("College Details").font(.inter(16, .semibold)).foregroundStyle(.white).lineLimit(1)
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .background(AppColors.primary)
      AuthWebView(
        url: APIClient.shared.url(
          "college/full-details/\(route.collegeId)/webview/", query: ["councelling_type": route.counselling]))
    }
    .background(AppColors.primary.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
  }
}

// MARK: - CutOffs & Matchings / Allotments

/// A filter line, "Sort by" and the server-rendered list (it draws its own
/// table and paging).
private struct WebListPage: View {
  let path: String
  let errorText: String
  let params: [String: String]
  let isSubscribed: Bool
  let openPremium: () -> Void

  @EnvironmentObject private var app: AppState
  @State private var from = ""
  @State private var to = ""
  @State private var reload = 0
  @State private var failed = false
  @State private var sorting = false
  @State private var fromText = ""
  @State private var toText = ""

  /// MY_COLLEGE_SIZE for subscribers, COLLEGE otherwise.
  private var limit: Int { isSubscribed ? 50 : 12 }

  private var url: URL {
    var query = params
    query["page"] = "1"
    query["limit"] = "\(limit)"
    if !from.isEmpty, !to.isEmpty, from != "0", to != "0" {
      query["range_from"] = from
      query["range_to"] = to
    }
    return APIClient.shared.url(path, query: query)
  }

  private var filterBy: String {
    let category = params["category"]
    if (params["councelling_type"] ?? "AIC") == "AIC" {
      return "Filter By: AIC\(category.map { "/\($0)" } ?? "")"
    }
    return "Filter By: \(params["state"].map { "\($0)/" } ?? "")\(category ?? "SC")"
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center) {
        Text(filterBy).font(.inter(11)).foregroundStyle(.black)
        Spacer(minLength: 8)
        Button {
          fromText = from == "0" ? "" : from
          toText = to == "0" ? "" : to
          sorting = true
        } label: {
          HStack(spacing: 4) {
            Text("Sort by").font(.inter(12, .semibold))
            Image("ic_baseline_sort_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
          }
          .foregroundStyle(AppColors.primary)
          .padding(EdgeInsets(top: 1, leading: 14, bottom: 1, trailing: 10))
          .background(filterMuted, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(filterStroke))
        }
        .buttonStyle(.plain)
      }
      .padding(.leading, 19).padding(.trailing, 16).padding(.top, 6).padding(.bottom, 4)

      if failed {
        VStack(spacing: 20) {
          Text(errorText).font(.inter(16, .bold)).foregroundStyle(AppColors.primary).multilineTextAlignment(.center)
          FilterButton(label: "Retry", height: 48) {
            failed = false
            reload += 1
          }
        }
        .padding(EdgeInsets(top: 64, leading: 32, bottom: 0, trailing: 32))
        .frame(maxHeight: .infinity, alignment: .top)
      } else {
        AuthWebView(url: url, onError: { failed = true }).id(reload)
      }
      if !isSubscribed {
        PremiumPrompt(textColor: grey47, buttonColor: AppColors.primary, buttonTextColor: .white, action: openPremium)
          .padding(.vertical, 10)
      }
    }
    .background(.white, in: RoundedCornersShape(topLeadingRadius: 24, topTrailingRadius: 24))
    .clipShape(RoundedCornersShape(topLeadingRadius: 24, topTrailingRadius: 24))
    .background(Color(hex: 0xF5F5F5))
    .compatTextAlert(
      "Sort by", isPresented: $sorting,
      fields: [
        CompatAlertField(placeholder: "From rank", text: $fromText),
        CompatAlertField(placeholder: "To rank", text: $toText),
      ],
      confirm: "Apply"
    ) {
      let f = fromText.filter(\.isNumber)
      let t = toText.filter(\.isNumber)
      if f.isEmpty || f == "0" { return app.show("Please enter from Rank") }
      if t.isEmpty || t == "0" { return app.show("Please enter to Rank") }
      from = f
      to = t
      failed = false
      reload += 1
    }
  }
}
