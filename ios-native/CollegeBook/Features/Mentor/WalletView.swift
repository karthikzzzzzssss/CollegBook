import SwiftUI

/// UserWalletRelatedActivity (activity_user_wallet_related.xml): the balance,
/// a grid of top-up amounts and a custom amount, paid through Razorpay.
private let walletCanvas = Color(hex: 0xF3F5F4)

struct WalletView: View {
  /// Back to the tab's root after a successful top-up.
  let onDone: () -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var balance: String?
  @State private var custom = ""
  @State private var payment = RazorpayPayment()
  @State private var paying = false

  private static let amounts = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 24) {
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 20, height: 20)
            .foregroundStyle(.white)
            .extendedTapArea(horizontal: 12, vertical: 12)
        }
        .accessibilityLabel("Back")
        Text("Add money to wallet").font(.inter(16, .bold)).foregroundStyle(.white)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 16)
      .background(AppColors.primary)

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          balanceCard

          // GridLayoutManager(3): rows of three equal cells.
          VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: Self.amounts.count, by: 3)), id: \.self) { start in
              HStack(alignment: .top, spacing: 10) {
                ForEach(start..<start + 3, id: \.self) { index in
                  if index < Self.amounts.count {
                    amountCard(Self.amounts[index]).frame(maxWidth: .infinity)
                  } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                  }
                }
              }
            }
          }
          .padding(.top, 16)

          Text("Or enter custom amount").font(.inter(15, .semibold)).foregroundStyle(Color(hex: 0x374151))
            .padding(.top, 28)
          customAmount.padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
      .background(walletCanvas)
    }
    .background(AppColors.primary.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
    .task { await loadBalance() }
  }

  /// The dark-green card with the balance.
  private var balanceCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Available Balance").font(.inter(14, .medium)).foregroundStyle(.white.opacity(0.85))
      Text(balance.map { "₹ \($0)" } ?? "₹ –").font(.inter(34, .bold)).foregroundStyle(.white)
        .lineLimit(1).minimumScaleFactor(0.6)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [Color(hex: 0x1E4B3E), Color(hex: 0x0A5A47)], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 18))
  }

  /// A pale-green amount button.
  private func amountCard(_ amount: Int) -> some View {
    Button {
      Task { await startPayment(amount) }
    } label: {
      Text("₹ " + String(amount)).font(.inter(17, .semibold)).foregroundStyle(Color(hex: 0x0B4F3C))
        .frame(maxWidth: .infinity).frame(height: 50)
        .background(Color(hex: 0xEEF6F1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xD5E6DC)))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add ₹\(amount)")
  }

  /// One rounded field: ₹, the amount, and the Add button.
  private var customAmount: some View {
    HStack(spacing: 10) {
      Text("₹").font(.inter(18, .bold)).foregroundStyle(appInk)
      TextField("", text: $custom, prompt: Text("Minimum ₹50").foregroundColor(Color(hex: 0x9CA3AF)))
        .font(.inter(18, .medium))
        .keyboardType(.numberPad)
        .onChangeCompat(of: custom) { _, new in
          let digits = new.filter(\.isNumber)
          if digits != new { custom = digits }
        }
      Button(action: addCustom) {
        Text("Add").font(.inter(15, .bold)).foregroundStyle(.white)
          .padding(.horizontal, 26).frame(height: 44)
          .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
    .padding(.leading, 18).padding(.trailing, 6)
    .frame(height: 56)
    .background(Color(hex: 0xF7F9F8), in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE3E6E8)))
  }

  private func loadBalance() async {
    // The native screen leaves the amount blank on failure.
    if let data = try? await app.api.object("auth/wallet/"), let value = data.string("balance") {
      balance = value
    }
  }

  private func addCustom() {
    let text = custom.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return app.show("Please enter an amount") }
    guard let value = Int(text) else { return app.show("Please enter a valid amount") }
    guard value >= 50 else { return app.show("Minimum amount is ₹50") }
    Task { await startPayment(value) }
  }

  private func startPayment(_ amount: Int) async {
    // A second tap while this one is under way.
    guard !paying else { return }
    paying = true
    defer { paying = false }
    let json: JSONObject
    do {
      json = try await app.api.request("POST", "college/payment/", body: ["amount": amount, "name": "MiniBrain"])
    } catch let error as APIError {
      app.show(
        error.payload == nil
          ? "Something went wrong. Please try again."
          : (error.payload?.string("message") ?? "Payment initiation failed"))
      return
    } catch {
      return app.show("Something went wrong. Please try again.")
    }
    guard let data = json.object("data"), let order = data.object("payment") else { return }
    let result = await payment.pay(
      name: data.string("name") ?? "MiniBrain User", description: "WalletPayment",
      amount: order.string("amount") ?? "", email: data.string("email") ?? "",
      contact: data.string("phone_number") ?? "", orderId: order.string("id") ?? "")
    switch result {
    case .failure(let error):
      app.show(error.message)
    case .success(let success):
      do {
        try await payment.confirm(success, api: app.api)
        try await app.api.request(
          "POST", "college/wallet/add-money/", body: ["amount": amount, "payment_id": success.orderId])
      } catch {
        // The money has been taken: stay put, but say so.
        app.show(RazorpayPayment.unconfirmedMessage)
        await loadBalance()
        return
      }
      onDone()
    }
  }
}
