import SwiftUI

private let gold = Color(hex: 0xE8BE5E)
private let secondary = Color(hex: 0x6B7280)
private let pageBg = Color(hex: 0xF6FAF7)

struct PlanFeature {
  let name: String
  let available: Bool
}

struct Plan: Identifiable {
  let id: String
  let name: String
  let description: String?
  let price: Int
  let features: [PlanFeature]

  init(_ json: JSONObject) {
    id = json.string("id") ?? ""
    name = json["name"] as? String ?? "Plan"
    description = json["description"] as? String
    price = json.int("price") ?? 0
    features = json.objects("features").map {
      PlanFeature(name: $0.string("feature_name") ?? "", available: $0.bool("is_available") == true)
    }
  }

  /// "₹24,999" — Indian digit grouping, as the native NumberFormat(en_IN).
  var priceText: String {
    let format = NumberFormatter()
    format.numberStyle = .decimal
    format.locale = Locale(identifier: "en_IN")
    return "₹\(format.string(from: NSNumber(value: price)) ?? "\(price)")"
  }
}

/// GET college/plan/: the plans, or nil when there are none / it failed.
func fetchPlans(_ api: APIClient) async -> [Plan]? {
  guard let json = try? await api.get("college/plan/") else { return nil }
  let plans = (json.object("data") ?? [:]).objects("results").map(Plan.init)
  return plans.isEmpty ? nil : plans
}

/// Buying a plan, as PremiumFragment / CollegePackagesActivity do it: POST
/// college/payment/ for an order, Razorpay checkout, then on success
/// college/payment/success/ and college/membership/ {plan_id, payment_id}.
/// Answers the membership call's message once a plan is bought.
@MainActor
func buyPlan(_ plan: Plan, app: AppState, payment: RazorpayPayment) async -> String? {
  let api = app.api
  // The native screens only log a failed order or payment.
  guard let json = try? await api.request("POST", "college/payment/", body: ["amount": plan.price, "name": "collegeplan"]),
    let data = json.object("data"), let order = data.object("payment")
  else { return nil }
  let result = await payment.pay(
    name: data.string("name") ?? "", description: "college packages", amount: order.string("amount") ?? "",
    email: data.string("email") ?? "", contact: data.string("phone_number") ?? "", orderId: order.string("id") ?? "")
  guard case .success(let success) = result else { return nil }
  do {
    try await payment.confirm(success, api: api)
    let membership = try await api.request(
      "POST", "college/membership/", body: ["plan_id": plan.id, "payment_id": success.orderId])
    return membership.string("message") ?? ""
  } catch {
    // The money has been taken: say so.
    app.show(RazorpayPayment.unconfirmedMessage)
    return nil
  }
}

private struct CardTop: PreferenceKey {
  static let defaultValue: [Int: CGFloat] = [:]
  static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
    value.merge(nextValue()) { $1 }
  }
}

/// The Premium tab — PremiumFragment (fragment_premium.xml).
struct PremiumView: View {
  /// Membership changed: the shell reloads it.
  let onPurchased: () -> Void

  @EnvironmentObject private var app: AppState
  @State private var plans: [Plan]?
  @State private var loading = true
  @State private var tab = 0
  @State private var ignoreScrollUntil = Date.distantPast
  @State private var payment = RazorpayPayment()
  @State private var paying = false
  @State private var contact = false

  var body: some View {
    CompatNavigationStack {
      VStack(spacing: 0) {
        TabHeader(title: "Premium")
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
              PremiumHero { contact = true }
              chooseHeading
              if loading && plans == nil {
                ProgressView().tint(AppColors.primary).controlSize(.large).frame(maxWidth: .infinity).padding(.top, 32)
              }
              if !loading && plans == nil {
                Text("No packages available right now. Pull down to refresh.").font(.inter(16, .bold))
                  .foregroundStyle(.black).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                  .padding(EdgeInsets(top: 32, leading: 32, bottom: 0, trailing: 32))
              }
              if let plans {
                Section {
                  ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                    PlanCard(plan: plan, index: index, count: plans.count) { buy(plan) }
                      .id(index)
                      .background(
                        GeometryReader { g in
                          Color.clear.preference(key: CardTop.self, value: [index: g.frame(in: .named("premium")).minY])
                        }
                      )
                      .padding(.horizontal, 16)
                  }
                  footer
                } header: {
                  if plans.count > 1 {
                    PlanTabs(names: plans.map(\.name), selected: tab) { index in
                      tab = index
                      ignoreScrollUntil = Date().addingTimeInterval(0.7)
                      withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .top) }
                    }
                    .padding(.vertical, 10)
                    .background(pageBg)
                  }
                }
              }
            }
            .padding(.bottom, 32)
            .tabletContentWidth()
          }
          .coordinateSpace(name: "premium")
          .onPreferenceChange(CardTop.self) { tops in
            // Highlights the plan under the pinned tabs.
            guard Date() > ignoreScrollUntil, let plans, plans.count > 1 else { return }
            var active = 0
            for (index, top) in tops where top <= 56 + 24 { active = max(active, index) }
            if active != tab { tab = active }
          }
          .pullToRefresh { await load() }
        }
        .background(pageBg)
      }
      .background(stateGreen.ignoresSafeArea(edges: .top))
      .hiddenNavigationBar()
      .compatDestination(isPresented: $contact) { ContactUsView() }
    }
    .task { if plans == nil { await load() } }
  }

  private func load() async {
    loading = true
    plans = await fetchPlans(app.api)
    loading = false
    tab = 0
  }

  private func buy(_ plan: Plan) {
    // A second tap while this one is under way.
    guard !paying else { return }
    paying = true
    Task {
      defer { paying = false }
      guard let message = await buyPlan(plan, app: app, payment: payment) else { return }
      app.show(message)
      onPurchased()
      await load()
    }
  }

  private var chooseHeading: some View {
    HStack(alignment: .bottom) {
      Text("Choose your plan").font(.inter(17, .semibold)).foregroundStyle(appInk)
      Spacer()
      Text("Tap a plan to select").font(.inter(12.5, .medium)).foregroundStyle(secondary).padding(.bottom, 1)
    }
    .padding(EdgeInsets(top: 22, leading: 20, bottom: 0, trailing: 20))
  }

  /// Secure-payments note and the "Not sure which plan is right?" card.
  private var footer: some View {
    VStack(spacing: 16) {
      HStack(spacing: 6) {
        Image("ic_plan_lock").renderingMode(.template).resizable().frame(width: 14, height: 14).foregroundStyle(secondary)
        Text("100% secure payments via Razorpay").font(.inter(11.5, .medium)).foregroundStyle(secondary)
      }
      Button {
        contact = true
      } label: {
        HStack(spacing: 12) {
          Image("ic_cb_support").renderingMode(.template).resizable().foregroundStyle(AppColors.primary).padding(10)
            .frame(width: 42, height: 42).background(.white, in: Circle())
            .overlay(Circle().stroke(Color(hex: 0xD6E8E0)))
          VStack(alignment: .leading, spacing: 2) {
            Text("Not sure which plan is right?").font(.inter(14.5, .semibold)).foregroundStyle(appInk)
            Text("Talk to our team – call or WhatsApp").font(.inter(12.5)).foregroundStyle(secondary)
          }
          Spacer()
          Image("ic_cb_chevron_right").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(AppColors.primary)
        }
        .padding(16)
        .background(
          LinearGradient(colors: [Color(hex: 0xEEF7F2), Color(hex: 0xD2E8DE)], startPoint: .topLeading, endPoint: .bottomTrailing),
          in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xD6E8E0)))
      }
      .buttonStyle(.plain)
    }
    .padding(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
  }
}

/// common_header_college_layout with search / premium hidden.
struct TabHeader: View {
  let title: String
  var onBack: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 20) {
      if let onBack {
        Button(action: onBack) {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 22, height: 22)
            .foregroundStyle(.white)
            .extendedTapArea(horizontal: 11, vertical: 11)
        }
        .accessibilityLabel("Back")
        .padding(.leading, -8)
      }
      Text(title).font(.inter(17, .bold)).foregroundStyle(.white)
      Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 15)
    .background(stateGreen)
  }
}

/// "Confused between plans?" (bg_premium_hero).
private struct PremiumHero: View {
  let onTalk: () -> Void

  var body: some View {
    HStack(spacing: 4) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Confused between plans?").font(.inter(17, .bold)).foregroundStyle(.white)
        Text("Our counsellors explain every plan and help you pick the right one.").font(.inter(12.5))
          .foregroundStyle(.white.opacity(0.85)).lineSpacing(4).padding(.top, 6)
        Button(action: onTalk) {
          Text("Talk to a counsellor  →").font(.inter(13, .semibold)).foregroundStyle(gold).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
      }
      Spacer(minLength: 0)
      Image("img_premium_counsellor").resizable().scaledToFit().frame(width: 168, height: 126)
        .accessibilityLabel("A counsellor explaining plans to students")
    }
    .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 6))
    .background {
      ZStack {
        LinearGradient(colors: [Color(hex: 0x0E5A49), Color(hex: 0x003A30)], startPoint: .topLeading, endPoint: .bottomTrailing)
        Circle().fill(.white.opacity(0.08)).frame(width: 220, height: 220).offset(x: 110, y: -80)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        Circle().fill(.white.opacity(0.06)).frame(width: 150, height: 150).offset(x: -40, y: 70)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    .padding(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
  }
}

/// item_premium_plan_tab.xml pills in a horizontal strip.
private struct PlanTabs: View {
  let names: [String]
  let selected: Int
  let onTap: (Int) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(names.enumerated()), id: \.offset) { index, name in
            Button {
              onTap(index)
            } label: {
              Text(name).font(.inter(13, .semibold)).lineLimit(1)
                .foregroundStyle(index == selected ? .white : Color(hex: 0x2B3A35))
                .padding(.horizontal, 16).frame(minHeight: 36)
                .background(index == selected ? AppColors.primary : .white, in: Capsule())
                .overlay(Capsule().stroke(index == selected ? .clear : Color(hex: 0xD6E3DE)))
            }
            .buttonStyle(.plain)
            .id(index)
            .accessibilityAddTraits(index == selected ? .isSelected : [])
          }
        }
        .padding(.horizontal, 16)
      }
      .onChangeCompat(of: selected) { _, index in withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(index) } }
    }
  }
}

/// row_services_plans.xml (CollegeServicePlansAdapter): green header band
/// with tier icon and price, the feature checklist, and its own buy button.
struct PlanCard: View {
  let plan: Plan
  let index: Int
  let count: Int
  let onContinue: () -> Void

  @State private var open = false
  private static let collapsed = 6

  /// Star, then crown, with a diamond for the last of three or more.
  private var icon: String {
    if count >= 3 && index == count - 1 { return "ic_plan_tier_diamond" }
    return index == 0 ? "ic_plan_tier_star" : "ic_plan_tier_crown"
  }

  var body: some View {
    // Included features first.
    let sorted = plan.features.filter(\.available) + plan.features.filter { !$0.available }
    let collapsible = sorted.count > Self.collapsed
    let shown = collapsible && !open ? Array(sorted.prefix(Self.collapsed)) : sorted
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 12) {
          Image(icon).renderingMode(.template).resizable().foregroundStyle(.white).padding(10)
            .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.25)))
          VStack(alignment: .leading, spacing: 2) {
            Text(plan.name).font(.inter(18, .bold)).foregroundStyle(.white)
            if let description = plan.description, !description.isEmpty {
              Text(description).font(.inter(12.5)).foregroundStyle(.white.opacity(0.85))
            }
          }
        }
        HStack(alignment: .lastTextBaseline, spacing: 8) {
          Text(plan.priceText).font(.inter(32, .bold)).foregroundStyle(.white)
          Text("one-time payment").font(.inter(12, .medium)).foregroundStyle(.white.opacity(0.7))
        }
      }
      .padding(EdgeInsets(top: 20, leading: 20, bottom: 18, trailing: 20))
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        ZStack {
          LinearGradient(colors: [Color(hex: 0x1A7A63), AppColors.primary], startPoint: .topLeading, endPoint: .bottomTrailing)
          Circle().fill(.white.opacity(0.08)).frame(width: 170, height: 170).offset(x: 60, y: -90)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          Circle().fill(.white.opacity(0.06)).frame(width: 90, height: 90).offset(x: -40, y: 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
      }
      .clipped()

      VStack(alignment: .leading, spacing: 0) {
        Text("WHAT'S INCLUDED").font(.inter(11, .semibold)).kerning(0.88).foregroundStyle(secondary).padding(.bottom, 6)
        ForEach(Array(shown.enumerated()), id: \.offset) { _, feature in
          HStack(alignment: .top, spacing: 12) {
            Image(feature.available ? "ic_plan_check" : "ic_plan_unavailable").resizable().frame(width: 18, height: 18)
              .padding(.top, 1)
            Text(feature.name).font(.inter(14, .medium)).foregroundStyle(feature.available ? appInk : secondary)
              .lineSpacing(7).opacity(feature.available ? 1 : 0.7)
          }
          .padding(.vertical, 6)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(feature.available ? "Included" : "Not included"): \(feature.name)")
        }
        if collapsible {
          Button(open ? "Show less" : "+ \(sorted.count - Self.collapsed) more features") { open.toggle() }
            .font(.inter(13.5, .semibold)).foregroundStyle(AppColors.primary).padding(.vertical, 6).padding(.top, 2)
        }
        Button(action: onContinue) {
          Text("Continue  ·  \(plan.priceText)").font(.inter(15, .bold)).kerning(0.15).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(LinearGradient(colors: [Color(hex: 0x1A7A63), AppColors.primary], startPoint: .leading, endPoint: .trailing), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
      }
      .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
    }
    .background(.white)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(hex: 0xDCE9E3)))
    .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
    .padding(EdgeInsets(top: 10, leading: 2, bottom: 8, trailing: 2))
  }
}

/// CollegePackagesActivity: "Packages", the same plan cards on white, opened
/// by "Get a Package" and "Go Premium to Apply". A bought plan returns home.
struct PackagesView: View {
  let onPurchased: () -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var plans: [Plan]?
  @State private var loading = true
  @State private var payment = RazorpayPayment()
  @State private var paying = false

  var body: some View {
    VStack(spacing: 0) {
      TabHeader(title: "Packages") { dismiss() }
      ScrollView {
        VStack(spacing: 0) {
          if plans == nil {
            if loading {
              ProgressView().tint(AppColors.primary).controlSize(.large).padding(.top, 32)
            } else {
              Text("No packages available right now.").font(.inter(16, .bold))
                .foregroundStyle(.black).multilineTextAlignment(.center).padding(.top, 32)
            }
          }
          ForEach(Array((plans ?? []).enumerated()), id: \.element.id) { index, plan in
            PlanCard(plan: plan, index: index, count: plans?.count ?? 0) {
              // A second tap while this one is under way.
              guard !paying else { return }
              paying = true
              Task {
                defer { paying = false }
                guard let message = await buyPlan(plan, app: app, payment: payment) else { return }
                app.show(message)
                onPurchased()
                dismiss()
              }
            }
          }
        }
        // Full width even with nothing in it: the white sheet takes its width from here.
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 32, trailing: 16))
      }
      .background(.white)
    }
    .background(Color.black.ignoresSafeArea())
    .hiddenNavigationBar()
    .task {
      plans = await fetchPlans(app.api)
      loading = false
    }
  }
}
