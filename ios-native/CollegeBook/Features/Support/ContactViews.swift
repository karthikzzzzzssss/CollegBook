import SwiftUI

private let secondary = Color(hex: 0x6B7280)
private let bodyText = Color(hex: 0x4B5563)
private let pageBg = Color(hex: 0xF6FAF7)

/// The dialer with the support number filled in (callSupport).
func callSupport() { Platform.call("+91\(supportPhone)") }

/// A WhatsApp chat with support; WhatsApp opens wa.me links itself, else
/// the browser does.
func whatsAppSupport() {
  let text = "Hi CollegeBook team, I need help with ".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
  Platform.open("https://wa.me/91\(supportPhone)?text=\(text)")
}

let shareAppText = """
  CollegeBook – by the doctor for the doctor 🩺

  NEET PG college cutoffs, rank-wise college matching, fee details, counselling choice lists and 1-to-1 video calls with PGs & faculty – all in one app.

  Download it free on the App Store:
  https://apps.apple.com/app/id6797748915
  """

/// layout_cb_header: green bar with back and title.
struct CbHeader: View {
  let title: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack(spacing: 12) {
      Button {
        dismiss()
      } label: {
        Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 22, height: 22)
          .foregroundStyle(.white).padding(9)
      }
      .accessibilityLabel("Back")
      Text(title).font(.inter(17, .bold)).foregroundStyle(.white).lineLimit(1)
      Spacer()
    }
    .padding(.leading, 4).padding(.trailing, 16)
    .frame(minHeight: 56)
    .background(stateGreen)
  }
}

/// A page with the CB header under a green status bar.
struct CbScaffold<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      CbHeader(title: title)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) { content }
          .padding(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
      }
      .background(pageBg)
    }
    .background(stateGreen.ignoresSafeArea())
    .hiddenNavigationBar()
    .coversTabBar()
  }
}

/// bg_cb_hero: gradient card with a round icon, title and text.
struct CbHero: View {
  let icon: String
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(icon).renderingMode(.template).resizable().foregroundStyle(.white).padding(12)
        .frame(width: 48, height: 48).background(.white.opacity(0.15), in: Circle())
      Text(title).font(.inter(22, .bold)).foregroundStyle(.white).padding(.top, 14).accessibilityAddTraits(.isHeader)
      Text(text).font(.inter(13.5)).foregroundStyle(.white.opacity(0.9)).lineSpacing(6).padding(.top, 8)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [stateGreen, AppColors.primary], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 20))
  }
}

extension View {
  /// The white 14pt card with a light outline.
  func cbCard() -> some View {
    background(.white, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE3E5E8)))
  }
}

struct CbPill: View {
  let label: String
  var icon: String? = nil
  var outline = false
  var height: CGFloat = 50
  let action: () -> Void

  var body: some View {
    let fg = outline ? stateGreen : Color.white
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Image(icon).renderingMode(.template).resizable().frame(width: 18, height: 18) }
        Text(label).font(.inter(15, .semibold))
      }
      .foregroundStyle(fg)
      .frame(maxWidth: .infinity).frame(height: height)
      .background(outline ? Color.white : stateGreen, in: Capsule())
      .overlay(Capsule().stroke(outline ? Color(hex: 0xD1D5DB) : .clear))
    }
    .buttonStyle(.plain)
  }
}

private func sectionTitle(_ text: String) -> some View {
  Text(text).font(.inter(16, .semibold)).foregroundStyle(appInk).padding(EdgeInsets(top: 22, leading: 4, bottom: 10, trailing: 0))
}

/// ContactUsActivity (activity_contact_us.xml).
struct ContactUsView: View {
  var body: some View {
    CbScaffold(title: "Contact Us") {
      CbHero(
        icon: "ic_cb_support", title: "We're here to help",
        text: "Questions about counselling, mentor calls, payments or your account? Talk to the CollegeBook team.")
      VStack(spacing: 0) {
        Text("Call or WhatsApp us").font(.inter(13, .medium)).foregroundStyle(secondary)
        Text(supportPhoneDisplay).font(.inter(26, .bold)).foregroundStyle(appInk).textSelection(.enabled).padding(.top, 4)
        HStack(spacing: 12) {
          CbPill(label: "Call now", icon: "ic_cb_phone", action: callSupport)
          CbPill(label: "WhatsApp", icon: "ic_cb_chat", outline: true, action: whatsAppSupport)
        }
        .padding(.top, 18)
      }
      .padding(20)
      .frame(maxWidth: .infinity)
      .cbCard()
      .padding(.top, 16)
      sectionTitle("We can help you with")
      Text(
        "•  Using cutoffs, matching and choice lists\n•  Booking or joining a mentor call\n•  Wallet top-ups and payments\n•  Premium packages\n•  Login or account problems\n•  Becoming a mentor on CollegeBook"
      )
      .font(.inter(13.5)).foregroundStyle(bodyText).lineSpacing(8)
      .padding(16).frame(maxWidth: .infinity, alignment: .leading).cbCard()
      sectionTitle("Policies")
      PolicyLinks()
    }
  }
}

enum SupportRoute: Hashable {
  case contact
  case legal(LegalDoc)
}

/// Privacy Policy and Terms & Conditions rows (item_cb_link_row.xml).
struct PolicyLinks: View {
  /// About's "Help & legal": a Contact Us row first.
  var withContact = false

  var body: some View {
    VStack(spacing: 0) {
      if withContact {
        row("ic_cb_support", "Contact Us", "Call or WhatsApp \(supportPhoneDisplay)", .contact)
      }
      row("ic_cb_privacy", "Privacy Policy", "How we collect and protect your data", .legal(.privacy))
      row("ic_cb_terms", "Terms & Conditions", "The rules for using CollegeBook", .legal(.terms))
    }
    .padding(.vertical, 4)
    .cbCard()
  }

  private func row(_ icon: String, _ title: String, _ subtitle: String, _ route: SupportRoute) -> some View {
    NavigationLink {
      switch route {
      case .contact: ContactUsView()
      case .legal(let doc): LegalDocumentView(doc: doc)
      }
    } label: {
      HStack(spacing: 14) {
        Image(icon).renderingMode(.template).resizable().foregroundStyle(stateGreen).padding(10)
          .frame(width: 40, height: 40).background(Color(hex: 0xE6EEEA), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.inter(14.5, .semibold)).foregroundStyle(appInk)
          Text(subtitle).font(.inter(12.5)).foregroundStyle(secondary)
        }
        Spacer(minLength: 8)
        Image("ic_cb_chevron_right").renderingMode(.template).resizable().frame(width: 24, height: 24).foregroundStyle(secondary)
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      .frame(minHeight: 64)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// LegalDocumentActivity: Privacy Policy or Terms & Conditions.
struct LegalDocumentView: View {
  let doc: LegalDoc

  var body: some View {
    CbScaffold(title: doc.title) {
      CbHero(icon: doc == .privacy ? "ic_cb_privacy" : "ic_cb_terms", title: doc.title, text: doc.intro)
        .padding(.bottom, 4)
      ForEach(Array(doc.sections.enumerated()), id: \.offset) { index, section in
        HStack(alignment: .top, spacing: 12) {
          Text("\(index + 1)").font(.inter(12, .semibold)).foregroundStyle(.white)
            .frame(width: 26, height: 26).background(stateGreen, in: Circle()).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 8) {
            Text(section.0).font(.inter(15, .semibold)).foregroundStyle(appInk).accessibilityAddTraits(.isHeader)
            Text(section.1).font(.inter(14)).foregroundStyle(bodyText).lineSpacing(8).textSelection(.enabled)
          }
          .padding(.top, 2)
          Spacer(minLength: 0)
        }
        .padding(16)
        .cbCard()
        .padding(.top, 12)
      }
      VStack(spacing: 0) {
        Text("Still have a question?").font(.inter(15, .semibold)).foregroundStyle(appInk)
        Text("Our team is a call or a WhatsApp message away.").font(.inter(13)).foregroundStyle(secondary)
          .multilineTextAlignment(.center).padding(.top, 4)
        NavigationLink {
          ContactUsView()
        } label: {
          Text("Contact Us").font(.inter(15, .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 48).background(stateGreen, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
      }
      .padding(20)
      .frame(maxWidth: .infinity)
      .cbCard()
      .padding(.top, 20)
    }
  }
}

/// AboutActivity (activity_about.xml).
struct AboutView: View {
  private static let features = [
    ("ic_building", "Explore colleges", "Courses, seats, fellowships, facilities and student Q&A for medical colleges across India."),
    ("ic_cb_file_csv", "Cutoffs & rank-wise matching", "Previous years' closing ranks by quota and category, and the colleges that match your rank."),
    ("ic_payment", "Fee details", "Tuition and other fees, college by college, so you can compare before you choose."),
    ("icon_choicelist", "Counselling choice lists", "Build ordered choice lists for each counselling and download them as PDF or CSV."),
    ("ic_menu_mentor", "1-to-1 mentor video calls", "Talk directly to PGs and faculty about their hospital, workload and training. Save favourites."),
    ("ic_play_arrow", "Webinars & video guides", "Step-by-step counselling guides, reels and expert webinars."),
    ("ic_about", "Updates & community", "Counselling deadlines, official notices and discussions with fellow aspirants."),
    ("school_24px", "Become a mentor", "Already a PG or faculty member? Register as a mentor and guide aspirants."),
  ]

  var body: some View {
    CbScaffold(title: "About") {
      VStack(spacing: 0) {
        Image("home_app_icon").resizable().scaledToFit().padding(6).frame(width: 80, height: 80)
          .background(.white.opacity(0.15), in: Circle())
        Text("CollegeBook").font(.inter(24, .bold)).foregroundStyle(.white).padding(.top, 12)
        Text("by the doctor for the doctor").font(.inter(13.5, .medium)).foregroundStyle(.white.opacity(0.9)).padding(.top, 2)
      }
      .padding(EdgeInsets(top: 24, leading: 20, bottom: 22, trailing: 20))
      .frame(maxWidth: .infinity)
      .background(
        LinearGradient(colors: [stateGreen, AppColors.primary], startPoint: .topLeading, endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: 20))

      VStack(alignment: .leading, spacing: 0) {
        Text("Our mission").font(.inter(13, .semibold)).foregroundStyle(stateGreen)
        Text("Turn your NEET PG rank into the right seat.").font(.inter(17, .bold)).foregroundStyle(appInk).padding(.top, 6)
        Text(
          "After NEET PG, every aspirant faces the same hard question: which college and course should I lock? The answers are scattered across counselling PDFs, college websites and word of mouth. CollegeBook brings it together – verified cutoffs, seats and fees, a smart way to plan your choices, and direct calls with PGs and faculty who already study and work there – so you can decide with confidence, not guesswork."
        )
        .font(.inter(13.5)).foregroundStyle(bodyText).lineSpacing(6).padding(.top, 10)
      }
      .padding(18)
      .cbCard()
      .padding(.top, 16)

      sectionTitle("What you can do")
      VStack(spacing: 0) {
        ForEach(Self.features, id: \.1) { icon, title, body in
          HStack(alignment: .top, spacing: 14) {
            Image(icon).renderingMode(.template).resizable().foregroundStyle(stateGreen).padding(10)
              .frame(width: 40, height: 40).background(Color(hex: 0xE6EEEA), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
              Text(title).font(.inter(14, .semibold)).foregroundStyle(appInk)
              Text(body).font(.inter(12.5)).foregroundStyle(secondary).lineSpacing(4)
            }
            Spacer(minLength: 0)
          }
          .padding(.vertical, 10)
        }
      }
      .padding(.horizontal, 16).padding(.vertical, 8)
      .cbCard()

      HStack(alignment: .top, spacing: 12) {
        Image("ic_cb_privacy").renderingMode(.template).resizable().frame(width: 22, height: 22).foregroundStyle(stateGreen)
        Text(
          "CollegeBook is an independent platform. We are not affiliated with MCC, NBEMS, NMC or any state counselling authority. Always confirm dates and data on the official portals before locking your choices."
        )
        .font(.inter(12.5)).foregroundStyle(stateGreen).lineSpacing(4)
      }
      .padding(16)
      .background(Color(hex: 0xE6EEEA), in: RoundedRectangle(cornerRadius: 14))
      .padding(.top, 16)

      sectionTitle("Help & legal")
      PolicyLinks(withContact: true)
      CompatShareLink(item: shareAppText, subject: "CollegeBook – NEET PG college guide") {
        HStack(spacing: 8) {
          Image("ic_share").renderingMode(.template).resizable().frame(width: 18, height: 18)
          Text("Share App").font(.inter(15, .semibold))
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52).background(stateGreen, in: Capsule())
      }
      .padding(.top, 22)
      CbPill(label: "★  Rate us on the App Store", outline: true, height: 52) {
        Platform.open("https://apps.apple.com/app/id6797748915?action=write-review")
      }
      .padding(.top, 12)
      Text("© \(String(Calendar.current.component(.year, from: Date()))) MiniBrain  ·  Made in India 🇮🇳").font(.inter(12))
        .foregroundStyle(secondary).frame(maxWidth: .infinity).padding(.top, 24)
    }
  }
}
