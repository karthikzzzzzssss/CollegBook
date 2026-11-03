import SwiftUI

/// NavigationView + nav_header_college + side_menu.xml: a 300pt drawer from
/// the leading edge.
struct SideMenu: View {
  @Binding var isOpen: Bool
  let onLogout: () -> Void
  let onDeleteAccount: () -> Void

  @EnvironmentObject private var app: AppState
  @State private var page: MenuPage?

  enum MenuPage: String, Identifiable {
    case mentor = "As a Mentor"
    case payments = "My Sessions"
    case contact = "Contact Us"
    case privacy = "Privacy Policy"
    case terms = "Terms & Conditions"
    case about = "About"
    var id: String { rawValue }
  }

  private static let shareText = """
    CollegeBook – by the doctor for the doctor 🩺

    NEET PG college cutoffs, rank-wise college matching, fee details, counselling choice lists and 1-to-1 video calls with PGs & faculty – all in one app.

    Download it free on the App Store:
    https://apps.apple.com/app/id6797748915
    """

  var body: some View {
    ZStack(alignment: .leading) {
      if isOpen {
        Color.black.opacity(0.4)
          .ignoresSafeArea()
          .onTapGesture { close() }
          .transition(.opacity)
          .accessibilityLabel("Close menu")
          .accessibilityAddTraits(.isButton)
      }
      if isOpen {
        drawer
          .frame(width: 300)
          .background(.white)
          .transition(.move(edge: .leading))
      }
    }
    .animation(.easeOut(duration: 0.25), value: isOpen)
    .gesture(DragGesture().onEnded { if $0.translation.width < -60 { close() } })
    .fullScreenCover(item: $page) { page in
      CompatNavigationStack {
        switch page {
        case .mentor: AsMentorView()
        case .payments: PaymentHistoryView()
        case .contact: ContactUsView()
        case .privacy: LegalDocumentView(doc: .privacy)
        case .terms: LegalDocumentView(doc: .terms)
        case .about: AboutView()
        }
      }
      .environmentObject(app)
    }
  }

  private var drawer: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        header
        VStack(spacing: 0) {
          item("ic_menu_mentor", "As a Mentor") { open(.mentor) }
          item("ic_payment", "My Sessions") { open(.payments) }
          CompatShareLink(item: Self.shareText, subject: "CollegeBook – NEET PG college guide") {
            row("ic_share", "Share App")
          }
          .buttonStyle(MenuButtonStyle())
          divider
          item("ic_cb_support", "Contact Us") { open(.contact) }
          item("ic_cb_privacy", "Privacy Policy") { open(.privacy) }
          item("ic_cb_terms", "Terms & Conditions") { open(.terms) }
          item("ic_about", "About") { open(.about) }
          divider
          item("ic_logout", "Logout") {
            close()
            onLogout()
          }
          item("ic_cb_delete", "Delete Account") {
            close()
            onDeleteAccount()
          }
        }
        .padding(.top, 8)
      }
    }
    .ignoresSafeArea(edges: .top)
  }

  private var header: some View {
    let profile = app.session.profile
    let name = profile.name?.trimmingCharacters(in: .whitespaces) ?? ""
    let phone = profile.phone.flatMap { $0.isEmpty ? nil : ($0.hasPrefix("+") ? $0 : "+91 \($0)") }
    return HStack(alignment: .top, spacing: 12) {
      ZStack {
        if let initial = name.first {
          Circle().fill(AppColors.allIndia)
          Circle().stroke(.white, lineWidth: 2)
          Text(String(initial).uppercased()).font(.inter(22, .bold)).foregroundStyle(AppColors.primary)
        } else {
          Image("home_iv_user_profile").resizable().scaledToFill().clipShape(Circle()).padding(2)
            .background(Color(hex: 0xEEF2F4), in: Circle())
        }
      }
      .frame(width: 50, height: 50)
      .padding(.top, 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(name.isEmpty ? "CollegeBook" : name).font(.inter(16, .bold)).foregroundStyle(.white)
        Text(phone ?? "by the doctor for the doctor").font(.inter(13)).foregroundStyle(.white.opacity(0.8))
      }
      .padding(.top, 20)
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 28, leading: 20, bottom: 22, trailing: 20))
    .safeAreaEdgePadding(.top)
    .background(AppColors.primary)
  }

  private var divider: some View {
    Rectangle().fill(Color(hex: 0x79747E)).frame(height: 1).padding(.horizontal, 28).padding(.vertical, 8)
  }

  private func item(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { row(icon, label) }.buttonStyle(MenuButtonStyle())
  }

  private func row(_ icon: String, _ label: String) -> some View {
    HStack(spacing: 20) {
      Image(icon).renderingMode(.template).resizable().scaledToFit()
        .frame(width: 22, height: 22).foregroundStyle(AppColors.primary)
      Text(label).font(.inter(15, .medium)).foregroundStyle(AppColors.title)
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 14)
    .contentShape(Rectangle())
  }

  private func open(_ target: MenuPage) {
    close()
    page = target
  }

  private func close() { isOpen = false }
}

/// The native item highlight: a pale-green stadium while pressed.
private struct MenuButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? AppColors.allIndia : .clear, in: Capsule())
      .padding(.horizontal, 12)
  }
}
