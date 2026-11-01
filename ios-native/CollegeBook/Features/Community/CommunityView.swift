import SwiftUI

/// DataProvider.counsellingStates — the state picker's list.
let counsellingStates = [
  "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana",
  "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya",
  "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
  "Uttar Pradesh", "Uttarakhand", "West Bengal", "Andaman and Nicobar Islands", "Chandigarh",
  "Dadra and Nagar Haveli and Daman and Diu", "Delhi", "Jammu and Kashmir", "Ladakh", "Lakshadweep", "Puducherry",
]

/// PreferenceManager.getDefaultState(): the counselling state, Telangana
/// until one is picked.
enum DefaultStateStore {
  private static let key = "college_guide_default_state"

  static var value: String {
    get {
      let saved = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
      return saved.isEmpty ? "Telangana" : saved
    }
    set { UserDefaults.standard.set(newValue, forKey: key) }
  }
}

/// The Community tab — CollegeQnATabsFragment: All India / state over Chats
/// and Q&A.
struct CommunityView: View {
  @State private var stateName = DefaultStateStore.value
  @State private var allIndiaSelected = true
  @State private var mode = 0  // 0 Chats, 1 Q&A
  @State private var pickingState = false
  @State private var asking = false
  @State private var qnaRefresh = 0

  var body: some View {
    CompatNavigationStack {
      VStack(spacing: 0) {
        header
        ZStack(alignment: .bottomTrailing) {
          GroupChatView(allIndia: allIndiaSelected, state: stateName, active: mode == 0)
            .opacity(mode == 0 ? 1 : 0)
            .allowsHitTesting(mode == 0)
          if mode == 1 {
            ZStack {
              QnaListView(selection: "All India", refreshToken: qnaRefresh, onAsk: { asking = true }) { qnaRefresh += 1 }
                .opacity(allIndiaSelected ? 1 : 0).allowsHitTesting(allIndiaSelected)
              QnaListView(selection: stateName, refreshToken: qnaRefresh, onAsk: { asking = true }) { qnaRefresh += 1 }
                .opacity(allIndiaSelected ? 0 : 1).allowsHitTesting(!allIndiaSelected)
            }
            askButton.padding(16)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xF2EDE4))
      }
      .background(stateGreen.ignoresSafeArea(edges: .top))
      .hiddenNavigationBar()
      .compatDestination(isPresented: $asking) { AskQuestionView(onPosted: posted) }
      .sheet(isPresented: $pickingState) { statePicker }
    }
  }

  /// Open the tab the question was tagged under, then reload both lists.
  private func posted(_ tags: String) {
    var allIndia = false
    var state = false
    for tag in tags.split(separator: ",") {
      let t = tag.trimmingCharacters(in: .whitespaces).lowercased()
      if t == "all india" { allIndia = true }
      if t == stateName.lowercased() { state = true }
    }
    if !((allIndiaSelected && allIndia) || (!allIndiaSelected && state)) {
      if allIndia { allIndiaSelected = true } else if state { allIndiaSelected = false }
    }
    qnaRefresh += 1
  }

  private var header: some View {
    VStack(spacing: 8) {
      HStack(spacing: 0) {
        chip("All India Counselling", selected: allIndiaSelected) { allIndiaSelected = true }
        chip(stateName, selected: !allIndiaSelected, dropdown: true) {
          // Already on the state: tapping again opens the picker.
          if allIndiaSelected { allIndiaSelected = false } else { pickingState = true }
        }
      }
      .padding(3)
      .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.25)))
      .padding(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))

      HStack(spacing: 0) {
        tab("Chats", 0)
        tab("Q&A", 1)
      }
    }
    .background(stateGreen)
  }

  private func chip(_ label: String, selected: Bool, dropdown: Bool = false, action: @escaping () -> Void) -> some View {
    let color = selected ? stateGreen : Color.white
    return Button(action: action) {
      HStack(spacing: 0) {
        Text(label).font(.inter(13, .bold)).foregroundStyle(color).lineLimit(1).frame(maxWidth: .infinity)
        if dropdown {
          Image("ic_baseline_arrow_drop_down_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(color)
        }
      }
      .padding(.leading, dropdown ? 12 : 8).padding(.trailing, dropdown ? 6 : 8)
      .frame(height: 36)
      .background(selected ? AppColors.allIndia : .clear, in: RoundedRectangle(cornerRadius: 9))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func tab(_ label: String, _ index: Int) -> some View {
    let selected = mode == index
    return Button {
      mode = index
    } label: {
      Text(label).font(.inter(13, .bold)).foregroundStyle(selected ? .white : .white.opacity(0.65))
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          if selected {
            RoundedCornersShape(topLeadingRadius: 3, topTrailingRadius: 3).fill(AppColors.allIndia).frame(height: 3)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// fab_ask: the compact "Ask" pill.
  private var askButton: some View {
    Button {
      asking = true
    } label: {
      HStack(spacing: 6) {
        Image("ic_edit_pencil_small").renderingMode(.template).resizable().frame(width: 16, height: 16)
        Text("Ask").font(.inter(14, .bold))
      }
      .foregroundStyle(.white)
      .padding(.leading, 14).padding(.trailing, 16).frame(height: 40)
      .background(AppColors.primary, in: Capsule())
      .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
    .buttonStyle(.plain)
  }

  /// specialty_bottomsheet_layout.xml: the states at 80% of the screen.
  private var statePicker: some View {
    ScrollView {
      VStack(spacing: 4) {
        ForEach(counsellingStates, id: \.self) { s in
          Button {
            DefaultStateStore.value = s
            stateName = s
            allIndiaSelected = false
            pickingState = false
          } label: {
            Text(s).font(.inter(16, .medium)).foregroundStyle(s == stateName ? .white : .black)
              .frame(maxWidth: .infinity).padding(10)
              .background(s == stateName ? Color(hex: 0x283593) : .white, in: RoundedRectangle(cornerRadius: 4))
              .overlay(RoundedRectangle(cornerRadius: 4).stroke(s == stateName ? .clear : Color(hex: 0xD3DADE)))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)
    }
    .sheetDetents([.fraction(0.8)])
    .sheetDragIndicatorVisible()
    .sheetCornerRadius(18)
  }
}
