import SwiftUI

private struct CallItem: Identifiable {
  let id = UUID()
  let status: String
  let startTime: String?
  let duration: String
  let charged: Double
  let name: String?
  let image: String?

  init(_ json: JSONObject) {
    status = json.string("status") ?? ""
    startTime = json["start_time"] as? String
    duration = json.string("duration_formatted") ?? ""
    charged = json.double("total_charged") ?? 0
    name = json.object("counsellor")?["name"] as? String
    image = json.object("counsellor")?["image"] as? String
  }

  /// "18 Jul 2026, 06:19 AM" in local time (the API time is UTC).
  var date: String {
    guard let raw = startTime, !raw.isEmpty else { return "" }
    let parse = DateFormatter()
    parse.locale = Locale(identifier: "en_US_POSIX")
    parse.timeZone = TimeZone(identifier: "UTC")
    parse.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    guard let parsed = parse.date(from: String(raw.prefix(19))) else { return raw }
    let format = DateFormatter()
    format.dateFormat = "dd MMM yyyy, hh:mm a"
    return format.string(from: parsed)
  }

  /// ₹12 or ₹12.75.
  var chargedText: String {
    "₹\(charged == charged.rounded(.down) ? String(Int(charged)) : String(format: "%.2f", charged))"
  }

  var statusColor: Color {
    switch status {
    case "ONGOING": Color(hex: 0x4CAF50)
    case "COMPLETED": Color(hex: 0x9E9E9E)
    default: Color(hex: 0xE53935)
    }
  }
}

/// PaymentHistoryActivity: the user's mentor calls, 10 per page.
struct PaymentHistoryView: View {
  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var items: [CallItem] = []
  @State private var page = 1
  @State private var loading = false
  @State private var hasNext = true
  @State private var firstLoad = true
  @State private var empty = false

  var body: some View {
    VStack(spacing: 0) {
      // MaterialToolbar: 55pt, back icon, 16pt Inter bold title.
      HStack(spacing: 4) {
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(.white).frame(width: 56, height: 55)
        }
        .accessibilityLabel("Back")
        Text("My Sessions").font(.inter(16, .bold)).foregroundStyle(.white)
        Spacer()
      }
      .frame(height: 55)
      .background(AppColors.primary)

      ZStack {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
              row(item).onAppear {
                if index >= items.count - 2, !loading, hasNext {
                  page += 1
                  loading = true
                  Task { await load() }
                }
              }
            }
          }
          .padding(EdgeInsets(top: 0, leading: 4, bottom: 16, trailing: 4))
        }
        if firstLoad && loading { ProgressView().controlSize(.large) }
        if empty { Text("No call history found").font(.inter(14)).foregroundStyle(Color(hex: 0x9E9E9E)) }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.white)
    }
    .background(Color.black.ignoresSafeArea())
    .hiddenNavigationBar()
    .task { if firstLoad { await load() } }
  }

  /// item_call_history.xml.
  private func row(_ item: CallItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      NetImage(item.image, placeholder: "ic_profile").frame(width: 48, height: 48).clipShape(Circle())
      VStack(alignment: .leading, spacing: 0) {
        Text(item.name ?? "-").font(.inter(15, .bold)).foregroundStyle(.black)
        Text(item.duration).font(.inter(13)).foregroundStyle(Color(hex: 0x757575)).padding(.top, 4)
        Text(item.date).font(.inter(12)).foregroundStyle(Color(hex: 0x9E9E9E)).padding(.top, 2)
      }
      Spacer(minLength: 0)
      VStack(alignment: .trailing, spacing: 8) {
        Text(item.status).font(.inter(11, .bold)).foregroundStyle(.white)
          .padding(.horizontal, 10).padding(.vertical, 3).background(item.statusColor, in: Capsule())
        Text(item.chargedText).font(.inter(14, .bold)).foregroundStyle(Color(hex: 0x283593))
      }
    }
    .padding(12)
    .background(.white, in: RoundedRectangle(cornerRadius: 6))
    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
    .padding(4)
  }

  private func load() async {
    loading = true
    defer {
      loading = false
      firstLoad = false
    }
    // Logged only, as natively.
    guard let data = try? await app.api.object("college/call/history/", query: ["page": "\(page)", "limit": "10"]) else {
      // The next scroll asks for this page again.
      if page > 1 { page -= 1 }
      return
    }
    let results = data.objects("results").map(CallItem.init)
    hasNext = data.bool("next") == true
    if firstLoad { empty = results.isEmpty }
    items += results
  }
}
