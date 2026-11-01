import SwiftUI

/// The Material 3 BottomNavigationView as the native app styles it: brand
/// bar, 26pt untinted icons, a pale-green pill behind the selected one and
/// 10pt Inter labels. Like a UITabBar it tucks part-way into the home
/// indicator inset.
struct BottomNavBar: View {
  @Binding var selected: HomeTab

  var body: some View {
    HStack(spacing: 0) {
      ForEach(HomeTab.allCases) { tab in
        item(tab)
      }
    }
    .frame(height: 60)
    .padding(.bottom, bottomInset)
    .background(AppColors.primary)
    // Like a UITabBar, the labels stay one size whatever the Text Size setting.
    .dynamicTypeSize(.large)
  }

  private var bottomInset: CGFloat {
    let inset =
      (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.bottom ?? 0
    return max(inset - 14, 0)
  }

  private func item(_ tab: HomeTab) -> some View {
    let isSelected = tab == selected
    return Button {
      selected = tab
    } label: {
      VStack(spacing: 2) {
        Image("nav_\(tab.icon)_\(isSelected ? "select" : "unselect")")
          .resizable()
          .scaledToFit()
          .frame(width: 26, height: 26)
          .frame(maxWidth: 64)
          .frame(height: 32)
          .background(isSelected ? AppColors.allIndia : .clear, in: Capsule())
          .padding(.horizontal, 4)
        Text(tab.title)
          .font(.inter(10, isSelected ? .bold : .medium))
          .foregroundStyle(AppColors.navLabel)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .padding(.top, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
