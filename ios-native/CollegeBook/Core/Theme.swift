import SwiftUI

/// lib/theme/app_theme.dart's AppColors, plus the native app's named colours.
enum AppColors {
  static let primary = Color(hex: 0x004D40)
  static let deepGreen = Color(hex: 0x1E4B3E)
  static let canvas = Color(hex: 0xF5F7F6)
  static let ink = Color(hex: 0x202522)
  static let muted = Color(hex: 0x6B7280)
  static let border = Color(hex: 0xE1E8E4)
  /// Native `all_india` / `bg_color`: the pale green of pills and highlights.
  static let allIndia = Color(hex: 0xE0FFC2)
  /// Native `text_color`: bottom-nav labels.
  static let navLabel = Color(hex: 0xB2DFBB)
  static let title = Color(hex: 0x1C1E21)
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: alpha)
  }
}

/// A pushed screen covers the bottom tab bar, as a Flutter route over the
/// home shell did.
private struct CoversTabBar: ViewModifier {
  @EnvironmentObject private var app: AppState
  func body(content: Content) -> some View {
    content
      .onAppear { app.coveringScreens += 1 }
      .onDisappear { app.coveringScreens = max(app.coveringScreens - 1, 0) }
  }
}

extension View {
  func coversTabBar() -> some View { modifier(CoversTabBar()) }

  /// Grows a small button's touch area toward 44pt without moving anything: the
  /// bars keep the native app's measurements.
  func extendedTapArea(horizontal: CGFloat, vertical: CGFloat) -> some View {
    padding(.horizontal, horizontal).padding(.vertical, vertical)
      .contentShape(Rectangle())
      .padding(.horizontal, -horizontal).padding(.vertical, -vertical)
  }
}

extension Font {
  /// The bundled Inter faces (Config/Info.plist UIAppFonts).
  static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let face: String
    switch weight {
    case .black, .heavy: face = "Inter-ExtraBold"
    case .bold: face = "Inter-Bold"
    case .semibold: face = "Inter-SemiBold"
    case .medium: face = "Inter-Medium"
    default: face = "Inter-Regular"
    }
    return .custom(face, size: size)
  }
}
