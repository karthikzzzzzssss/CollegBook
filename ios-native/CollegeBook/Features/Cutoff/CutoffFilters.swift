import SwiftUI

let stateGreen = Color(hex: 0x1E4B3E)
let appInk = Color(hex: 0x12151B)
let grey47 = Color(hex: 0x474747)
let grey666 = Color(hex: 0x666666)
let filterMuted = Color(hex: 0xF4F5F7)
let filterDivider = Color(hex: 0xECEDF0)
let filterSecondary = Color(hex: 0x6B7280)
let filterStroke = Color(hex: 0xE3E5E8)

/// One option in a filter list (LevelsNTagsModel): its status IS the selection.
final class FilterOption: Identifiable {
  let name: String
  var selected: Bool { willSet { willChange?() } }
  /// Set by the filter state holding this option: told before each change so
  /// the sheet showing it redraws.
  var willChange: (() -> Void)?
  var id: ObjectIdentifier { ObjectIdentifier(self) }
  init(_ name: String, _ selected: Bool) {
    self.name = name
    self.selected = selected
  }
}

/// The filter state the native fragment keeps in fields, so it survives
/// closing and reopening the sheet.
@MainActor final class CutoffFilterState: ObservableObject {
  let api: APIClient

  @Published var counselling = "AIC"
  @Published var rank = "0"
  @Published var defaultState = ""
  @Published var finalState: String?
  @Published var defaultCaste: String?
  @Published var finalCaste: String?
  @Published var defaultQuota: String?
  @Published var finalQuota: String?
  @Published var userPickedState = false
  @Published var stateHandled = false
  @Published var allIndiaHandled = false

  @Published var aicStates: [FilterOption] = [] { didSet { adopt(aicStates) } }
  @Published var aicSpecialities: [FilterOption] = [] { didSet { adopt(aicSpecialities) } }
  @Published var aicCastes: [FilterOption] = [] { didSet { adopt(aicCastes) } }
  @Published var aicQuotas: [FilterOption] = [] { didSet { adopt(aicQuotas) } }
  @Published var scStates: [FilterOption] = [] { didSet { adopt(scStates) } }
  @Published var scSpecialities: [FilterOption] = [] { didSet { adopt(scSpecialities) } }
  @Published var scCastes: [FilterOption] = [] { didSet { adopt(scCastes) } }
  @Published var scQuotas: [FilterOption] = [] { didSet { adopt(scQuotas) } }

  @Published var indiaStates: String?
  @Published var indiaSpecialities: String?
  @Published var stateSpecialities: String?

  /// The latest state load: an older response, or one for a closed sheet, is dropped.
  private var stateRequest = 0
  private var stateLoadPending = false

  init(api: APIClient) { self.api = api }

  /// Options redraw this state's views when they change.
  private func adopt(_ list: [FilterOption]) {
    for option in list { option.willChange = { [weak self] in self?.objectWillChange.send() } }
  }

  private func merge(_ list: inout [FilterOption], _ name: String?, _ selected: Bool) {
    guard let name, !list.contains(where: { $0.name == name }) else { return }
    list.append(FilterOption(name, selected))
  }

  static func join(_ list: [FilterOption]) -> String? {
    let names = list.filter(\.selected).map(\.name)
    return names.isEmpty ? nil : names.joined(separator: ",")
  }

  /// college/dropdwon/{AIC|SC}: filter options and defaults.
  private func filters(_ type: String, state: String? = nil) async throws -> JSONObject {
    try await api.object("college/dropdwon/\(type)", query: state.map { ["state_name": $0] } ?? [:])
  }

  /// Native setAPICallForHomeFilters().
  func loadHomeFilters() async {
    guard let data = try? await filters(counselling), let defaults = data.object("default_parameter") else { return }
    if finalCaste == nil { defaultCaste = defaults["category"] as? String }
    if finalQuota == nil { defaultQuota = defaults["quota"] as? String }
    if rank == "0" { rank = defaults.string("rank") ?? "0" }
    for s in data.objects("states") {
      merge(&aicStates, s["name"] as? String, s.bool("is_default") == true)
      merge(&scStates, s["name"] as? String, s.bool("is_default") == true)
    }
    for c in data.objects("category") { merge(&aicCastes, c["category"] as? String, c.bool("is_default") == true) }
    for q in data.objects("quota") { merge(&aicQuotas, q["name"] as? String, q.bool("is_default") == true) }
    for s in data.objects("speciality") { merge(&aicSpecialities, s["name"] as? String, s.bool("is_default") == true) }
    if indiaStates == nil { indiaStates = Self.join(aicStates) }
    if indiaSpecialities == nil { indiaSpecialities = Self.join(aicSpecialities) }
  }

  /// Native setupAllIndiaFilters() for the Category list.
  func loadAllIndiaFilters() async {
    guard let data = try? await filters("AIC"), let defaults = data.object("default_parameter") else { return }
    for c in data.objects("category") { merge(&aicCastes, c["category"] as? String, c.bool("is_default") == true) }
    for q in data.objects("quota") { merge(&aicQuotas, q["name"] as? String, q.bool("is_default") == true) }
    if finalCaste == nil { defaultCaste = defaults["category"] as? String }
    if finalQuota == nil { defaultQuota = defaults["quota"] as? String }
  }

  /// Native setUPForStatewithQuota(): one state's Category/Quota/Speciality.
  /// False only when this load, still the latest, failed. The lists are
  /// replaced on success, so a failure leaves the last loaded state's in place.
  @discardableResult
  func loadStateFilters(_ state: String?, picked: Bool = false) async -> Bool {
    guard let state, !state.isEmpty else {
      await loadDefaultStateThenFilters()
      return true
    }
    stateRequest += 1
    let request = stateRequest
    stateLoadPending = true
    let response = try? await filters("SC", state: state)
    guard request == stateRequest else { return true }
    stateLoadPending = false
    guard let data = response, let defaults = data.object("default_parameter") else {
      // Allow a retry, and don't pair the failed state with the lists on show.
      stateHandled = false
      if picked {
        finalState = defaultState.isEmpty ? nil : defaultState
        for o in scStates { o.selected = o.name == defaultState }
        if defaultState.isEmpty { userPickedState = false }
      }
      return false
    }
    let castes = data.objects("category").map { FilterOption($0["category"] as? String ?? "", $0.bool("is_default") == true) }
    let quotas = data.objects("quota").map { FilterOption($0["name"] as? String ?? "", $0.bool("is_default") == true) }
    var caste = defaults["category"] as? String
    var quota = defaults["quota"] as? String
    // Reopening the sheet reloads the same state: what the user chose stays
    // if it still exists. Picking a new state starts from that state's defaults.
    if !picked {
      if let kept = finalCaste, castes.contains(where: { $0.name == kept }) {
        caste = kept
        for o in castes { o.selected = o.name == kept }
      }
      if let kept = finalQuota, quotas.contains(where: { $0.name == kept }) {
        quota = kept
        for o in quotas { o.selected = o.name == kept }
      }
      scStates.removeAll()
    }
    defaultQuota = quota
    defaultCaste = caste
    finalQuota = quota
    finalCaste = caste
    scCastes = castes
    scQuotas = quotas
    for s in data.objects("states") { merge(&scStates, s["name"] as? String, s.bool("is_default") == true) }
    for s in data.objects("speciality") { merge(&scSpecialities, s["name"] as? String, s.bool("is_default") == true) }
    if stateSpecialities == nil { stateSpecialities = Self.join(scSpecialities) }
    defaultState = state
    return true
  }

  private func loadDefaultStateThenFilters() async {
    stateRequest += 1
    let request = stateRequest
    stateLoadPending = true
    let data = try? await api.object(
      "college/homepage", query: ["page": "1", "limit": "1", "councelling_type": "SC", "query": "institute"])
    guard request == stateRequest else { return }
    stateLoadPending = false
    guard let state = data?.object("default_parameter")?["state"] as? String, !state.isEmpty else {
      stateHandled = false
      return
    }
    setDefaultState(state, counselling: "SC")
    stateHandled = true
    // The state just read, not defaultState: it stays empty after a failed pick,
    // which would come straight back here.
    await loadStateFilters(state)
  }

  /// The sheet closed: a load still running must not change the filters, and
  /// the next open loads again.
  func cancelStateLoad() {
    guard stateLoadPending else { return }
    stateRequest += 1
    stateLoadPending = false
    stateHandled = false
  }

  /// CollegesFragment reports the SC list's default state.
  func setDefaultState(_ state: String?, counselling type: String?) {
    guard type == "SC", let state, !state.isEmpty, !userPickedState, state != defaultState else { return }
    defaultState = state
    finalState = state
    stateHandled = false
  }

  private static func summary(_ list: [FilterOption]) -> String? {
    let picked = list.filter(\.selected).map(\.name)
    if picked.isEmpty { return nil }
    return picked.count == 1 ? picked[0] : "\(picked.count) selected"
  }

  /// refreshFilterSummaries().
  func summary(_ key: String) -> String? {
    let aic = counselling == "AIC"
    switch key {
    case "State": return aic ? Self.summary(aicStates) : (finalState ?? defaultState)
    case "Speciality": return Self.summary(aic ? aicSpecialities : scSpecialities)
    case "Category": return defaultCaste
    default: return defaultQuota
    }
  }
}

/// The Filters sheet: counselling type, rank, then a key list (State,
/// Speciality, Category, Quota) beside its searchable options.
struct CutoffFilterSheet: View {
  @ObservedObject var filters: CutoffFilterState
  let isSubscribed: Bool
  let currentParams: [String: String]
  let onApply: ([String: String]) -> Void
  let onGoPremium: () -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var rank = ""
  @State private var search = ""
  @State private var key = "State"
  @State private var saved: (String, String?, String?, String?, String?)?
  @State private var applied = false
  @State private var closed = false

  private static let keys = ["State", "Speciality", "Category", "Quota"]
  private var f: CutoffFilterState { filters }
  private var aic: Bool { f.counselling == "AIC" }

  private var multi: Bool { (aic && (key == "State" || key == "Speciality")) || (!aic && key == "Speciality") }

  private var options: [FilterOption] {
    switch key {
    case "State": aic ? f.aicStates : f.scStates
    case "Speciality": aic ? f.aicSpecialities : f.scSpecialities
    case "Category": aic ? f.aicCastes : f.scCastes
    default: aic ? f.aicQuotas : f.scQuotas
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Filters").font(.inter(18, .semibold)).foregroundStyle(appInk)
        Spacer()
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_close").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(appInk).padding(6)
        }
        .accessibilityLabel("Close")
      }
      .padding(EdgeInsets(top: 15, leading: 20, bottom: 0, trailing: 12))

      HStack(spacing: 0) {
        ForEach([("AIC", "All India Counselling"), ("SC", "State Counselling")], id: \.0) { type, label in
          Button {
            setCounselling(type)
          } label: {
            Text(label).font(.inter(13, .medium)).lineLimit(1)
              .foregroundStyle(f.counselling == type ? .white : filterSecondary)
              .frame(maxWidth: .infinity).padding(.vertical, 10)
              .background(f.counselling == type ? AppColors.primary : .clear, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(4)
      .background(filterMuted, in: Capsule())
      .padding(EdgeInsets(top: 11, leading: 20, bottom: 0, trailing: 20))

      Text("Your Rank").font(.inter(13, .medium)).foregroundStyle(filterSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 20))
      FilterInput(text: $rank, hint: "Enter your rank").padding(.horizontal, 20)
      Rectangle().fill(filterDivider).frame(height: 1).padding(.top, 14)

      GeometryReader { geo in
        HStack(spacing: 0) {
          ScrollView {
            VStack(spacing: 0) {
              ForEach(Self.keys, id: \.self) { k in keyRow(k) }
            }
          }
          .frame(width: geo.size.width * 0.36)
          .background(filterMuted)

          VStack(spacing: 0) {
            FilterInput(text: $search, hint: "Search", height: 40, textSize: 14, number: false, searchIcon: true)
              .padding(EdgeInsets(top: 10, leading: 12, bottom: 0, trailing: 12))
            ScrollView {
              LazyVStack(spacing: 0) {
                let query = search.trimmingCharacters(in: .whitespaces).lowercased()
                ForEach(options.filter { query.isEmpty || $0.name.lowercased().contains(query) }) { option in
                  valueRow(option)
                }
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
            }
          }
        }
      }

      Rectangle().fill(filterDivider).frame(height: 1)
      FilterButton(label: isSubscribed ? "Apply Filters" : "Go Premium to Apply", height: 50) {
        if isSubscribed { apply() } else { onGoPremium() }
      }
      .padding(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
    }
    .background(.white)
    .sheetDetents([.fraction(0.85)])
    .sheetCornerRadius(20)
    .interactiveDismissDisabled()
    .onAppear {
      saved = (f.counselling, f.defaultQuota, f.finalQuota, f.defaultCaste, f.finalCaste)
      if f.rank != "0" { rank = f.rank }
      select("State")
    }
    .onDisappear {
      closed = true
      f.cancelStateLoad()
      // Restored if the sheet closes without Apply.
      guard !applied, let saved else { return }
      f.counselling = saved.0
      f.defaultQuota = saved.1
      f.finalQuota = saved.2
      f.defaultCaste = saved.3
      f.finalCaste = saved.4
    }
  }

  /// row_home_filter_key.xml.
  private func keyRow(_ k: String) -> some View {
    let selected = k == key
    return Button {
      select(k)
    } label: {
      HStack(spacing: 0) {
        RoundedRectangle(cornerRadius: 2).fill(selected ? AppColors.primary : .clear).frame(width: 3)
          .padding(.leading, 12)
        VStack(alignment: .leading, spacing: 2) {
          Text(k).font(.inter(14, selected ? .semibold : .medium))
          if let summary = f.summary(k), !summary.isEmpty {
            Text(summary).font(.inter(11)).lineLimit(1)
          }
        }
        .foregroundStyle(AppColors.primary)
        .padding(.leading, 7).padding(.trailing, 16)
        Spacer(minLength: 0)
      }
      .padding(.vertical, 10)
      .frame(minHeight: 56)
      .background(selected ? Color.white : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// row_home_filter_value.xml: a radio button or a checkbox.
  private func valueRow(_ option: FilterOption) -> some View {
    Button {
      if multi { toggle(option) } else { pick(option) }
    } label: {
      HStack(spacing: 8) {
        Image(
          systemName: multi
            ? (option.selected ? "checkmark.square.fill" : "square")
            : (option.selected ? "largecircle.fill.circle" : "circle")
        )
        .font(.system(size: 20))
        .foregroundStyle(stateGreen)
        .frame(width: 32)
        Text(option.name).font(.inter(14, .medium)).foregroundStyle(appInk).multilineTextAlignment(.leading)
        Spacer(minLength: 8)
      }
      .frame(minHeight: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(option.selected ? .isSelected : [])
  }

  /// handleFilterSelection().
  private func select(_ k: String) {
    // The number pad has no return key, and it covers the options.
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    search = ""
    key = k
    Task {
      if k == "State", !aic, !f.stateHandled {
        f.stateHandled = true
        await f.loadStateFilters(f.defaultState)
      } else if k == "Category", aic, !f.allIndiaHandled {
        f.allIndiaHandled = true
        await f.loadAllIndiaFilters()
      }
      adoptTicked()
    }
  }

  /// A ticked radio row is the value (onFilterValueSelected on bind).
  private func adoptTicked() {
    guard !closed, !multi, let option = options.first(where: \.selected) else { return }
    switch key {
    case "State": f.finalState = option.name
    case "Category":
      f.defaultCaste = option.name
      f.finalCaste = option.name
    default:
      f.defaultQuota = option.name
      f.finalQuota = option.name
    }
  }

  private func setCounselling(_ type: String) {
    if type == "AIC" {
      if !aic {
        f.defaultQuota = "AIQ"
        f.finalQuota = "AIQ"
        restore(f.aicCastes, f.aicQuotas)
      }
    } else if aic {
      restore(f.scCastes, f.scQuotas)
    }
    f.counselling = type
    select("State")
  }

  private func restore(_ castes: [FilterOption], _ quotas: [FilterOption]) {
    for o in castes where o.selected {
      f.defaultCaste = o.name
      f.finalCaste = o.name
    }
    for o in quotas where o.selected {
      f.defaultQuota = o.name
      f.finalQuota = o.name
    }
  }

  private func toggle(_ option: FilterOption) {
    option.selected.toggle()
    let joined = CutoffFilterState.join(options)
    if aic, key == "State" { f.indiaStates = joined }
    if aic, key == "Speciality" { f.indiaSpecialities = joined }
    if !aic, key == "Speciality" { f.stateSpecialities = joined }
  }

  /// onFilterValueSelected().
  private func pick(_ option: FilterOption) {
    for o in options { o.selected = false }
    option.selected = true
    switch key {
    case "State":
      f.finalState = option.name
      f.userPickedState = true
      Task {
        if await !f.loadStateFilters(option.name, picked: true) {
          app.show("Couldn't load this state's filters")
        }
        adoptTicked()
      }
    case "Category":
      f.defaultCaste = option.name
      f.finalCaste = option.name
    default:
      f.defaultQuota = option.name
      f.finalQuota = option.name
    }
  }

  private func apply() {
    let value = rank.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty, !value.allSatisfy({ $0 == "0" }) else {
      app.show("Please enter a valid Rank")
      return
    }
    f.rank = value
    var params = currentParams
    params["rank"] = value
    func put(_ key: String, _ value: String?) {
      if let value { params[key] = value } else { params.removeValue(forKey: key) }
    }
    if aic {
      params["councelling_type"] = "AIC"
      put("state", f.indiaStates)
      put("speciality", f.indiaSpecialities)
    } else {
      params["councelling_type"] = "SC"
      put("state", f.finalState)
      put("speciality", f.stateSpecialities)
    }
    if let caste = f.finalCaste { params["category"] = caste }
    if let quota = f.finalQuota { params["quota"] = quota }
    f.stateHandled = false
    f.allIndiaHandled = false
    applied = true
    onApply(params)
    dismiss()
  }
}

/// bg_filter_input: a muted box with 12pt corners.
struct FilterInput: View {
  @Binding var text: String
  let hint: String
  var height: CGFloat = 48
  var textSize: CGFloat = 15
  var number = true
  var searchIcon = false

  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      if searchIcon {
        Image("ic_baseline_search_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
          .foregroundStyle(filterSecondary)
      }
      TextField("", text: $text, prompt: Text(hint).foregroundColor(filterSecondary))
        .font(.inter(textSize, number ? .medium : .regular))
        .foregroundStyle(appInk)
        .keyboardType(number ? .numberPad : .default)
        .focused($focused)
        .onChangeCompat(of: text) { _, new in
          guard number else { return }
          // Digits only, at most 10, no leading zero.
          var digits = String(new.filter(\.isNumber).prefix(10))
          while digits.hasPrefix("0") { digits.removeFirst() }
          if digits != new { text = digits }
        }
    }
    .padding(.horizontal, searchIcon ? 12 : 16)
    .frame(height: height)
    .background(filterMuted, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? stateGreen : filterStroke, lineWidth: focused ? 1.5 : 1))
  }
}

/// bg_filter_button: brand green, 12pt corners.
struct FilterButton: View {
  let label: String
  let height: CGFloat
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label).font(.inter(15, .semibold)).foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: height)
        .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}
