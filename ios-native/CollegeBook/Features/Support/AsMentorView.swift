import SwiftUI

private let dark = Color(hex: 0x1C1E21)
private let grey = Color(hex: 0x6B7280)

/// MentorActivity + PGCounselorFragment: the user's mentor status.
struct AsMentorView: View {
  private enum Status { case loading, notRegistered, pending, approved, error }

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var status = Status.loading
  @State private var profile: JSONObject = [:]
  @State private var available = false
  @State private var savingAvailability = false
  @State private var sessions: [JSONObject] = []
  @State private var page = 1
  @State private var hasNext = true
  @State private var loadingHistory = false
  @State private var historyLoaded = false
  @State private var registering = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(.white).padding(8)
        }
        .accessibilityLabel("Back")
        Text("As a Mentor").font(.inter(18, .bold)).foregroundStyle(.white)
        Spacer()
      }
      .padding(.leading, 8)
      .frame(height: 56)
      .background(AppColors.primary)

      Group {
        if status == .loading {
          VStack(spacing: 12) {
            ProgressView().tint(AppColors.primary).controlSize(.large)
            Text("Checking your mentor status…").font(.inter(14, .medium)).foregroundStyle(grey)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            switch status {
            case .notRegistered: notRegistered
            case .pending: pending
            case .approved: approved
            default: errorView
            }
          }
        }
      }
      .background(Color(hex: 0xF4F7F6))
    }
    .background(AppColors.primary.ignoresSafeArea())
    .hiddenNavigationBar()
    .task { await fetchStatus() }
    .compatDestination(isPresented: $registering) { MentorRegistrationView() }
    .onChangeCompat(of: registering) { _, open in
      // onResume: re-check (now "under review" after a submit).
      if !open { Task { await fetchStatus() } }
    }
  }

  private func fetchStatus() async {
    var json: JSONObject?
    do {
      json = try await app.api.get("college/counsellor/")
    } catch let error as APIError {
      json = error.payload
    } catch {}
    switch json?.string("message") {
    case "COUNSELLOR_PROFILE":
      profile = json?.object("data") ?? [:]
      available = profile.bool("is_available") == true
      status = .approved
      page = 1
      hasNext = true
      sessions = []
      await fetchHistory()
    case "REGISTRATION_NOT_APPROVED": status = .pending
    case "REGISTRATION_NOT_FOUND": status = .notRegistered
    default: status = .error
    }
  }

  private func setAvailable(_ value: Bool) {
    available = value
    savingAvailability = true
    Task {
      var ok = false
      var saved = !value
      if let data = try? await app.api.request("PUT", "college/counsellor/profile/", body: ["is_available": value])
        .object("data")
      {
        saved = data.bool("is_available") == true
        ok = true
      }
      savingAvailability = false
      available = ok ? saved : !value
      if !ok { app.show("Couldn't update availability. Please try again.") }
    }
  }

  private func fetchHistory() async {
    loadingHistory = true
    // Logged only, as natively.
    if let data = try? await app.api.object("college/counsellor/call/history/", query: ["page": "\(page)", "limit": "20"]) {
      hasNext = data.bool("next") == true
      sessions += data.objects("results")
    } else if page > 1 {
      // The next scroll asks for this page again.
      page -= 1
    }
    loadingHistory = false
    historyLoaded = true
  }

  // MARK: States

  private func circle<Content: View>(_ size: CGFloat, _ color: Color, @ViewBuilder _ content: () -> Content) -> some View {
    content().frame(width: size, height: size).background(color, in: Circle())
  }

  private func icon(_ name: String, _ size: CGFloat, _ tint: Color) -> some View {
    Image(name).renderingMode(.template).resizable().frame(width: size, height: size).foregroundStyle(tint)
  }

  private func button(_ label: String, outline: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).font(.inter(16, .bold)).foregroundStyle(outline ? AppColors.primary : .white)
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(outline ? Color.white : AppColors.primary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(outline ? AppColors.primary : .clear, lineWidth: 1.5))
    }
    .buttonStyle(.plain)
  }

  private func card<Content: View>(
    padding: CGFloat = 18, spacing: CGFloat = 14, @ViewBuilder _ content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: spacing) { content() }
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE6ECEA)))
  }

  private func benefit(_ name: String, _ text: String) -> some View {
    HStack(spacing: 14) {
      circle(40, AppColors.allIndia) { icon(name, 20, AppColors.primary) }
      Text(text).font(.inter(14, .medium)).foregroundStyle(dark)
    }
  }

  private var notRegistered: some View {
    VStack(spacing: 0) {
      circle(120, AppColors.allIndia) { icon("ic_menu_mentor", 72, AppColors.primary) }
      Text("Become a CollegeBook Mentor").font(.inter(22, .bold)).foregroundStyle(dark).multilineTextAlignment(.center)
        .padding(.top, 24)
      Text("Share your experience with students choosing their college and branch.").font(.inter(14)).foregroundStyle(grey)
        .multilineTextAlignment(.center).lineSpacing(2).padding(.top, 8)
      card {
        benefit("ic_mentor_video", "Guide students on 1:1 video consultations")
        benefit("ic_mentor_rupee", "Earn per minute — you set your own fee")
        benefit("ic_mentor_badge", "Get a verified mentor badge on your profile")
      }
      .padding(.top, 28)
      button("Register as Mentor") { registering = true }.padding(.top, 28)
      Text("Takes about 2 minutes · reviewed in 24–48 hours").font(.inter(12)).foregroundStyle(Color(hex: 0x9CA3AF))
        .padding(.top, 12)
    }
    .padding(EdgeInsets(top: 32, leading: 24, bottom: 24, trailing: 24))
  }

  private var pending: some View {
    VStack(spacing: 0) {
      circle(120, Color(hex: 0xFFF4DB)) { icon("ic_mentor_hourglass", 60, Color(hex: 0xE0A100)) }
      Text("Application under review").font(.inter(22, .bold)).foregroundStyle(dark).padding(.top, 24)
      Text("We're reviewing your mentor application. This usually takes 24–48 hours.").font(.inter(14))
        .foregroundStyle(grey).multilineTextAlignment(.center).lineSpacing(2).padding(.top, 8)
      card(spacing: 16) {
        HStack(spacing: 14) {
          icon("ic_mentor_check", 24, Color(hex: 0x1E8E3E))
          Text("Application submitted").font(.inter(14, .medium)).foregroundStyle(dark)
        }
        HStack(spacing: 14) {
          icon("ic_mentor_hourglass", 24, Color(hex: 0xE0A100))
          VStack(alignment: .leading, spacing: 2) {
            Text("Under review").font(.inter(14, .semibold)).foregroundStyle(dark)
            Text("Our team is verifying your details").font(.inter(12)).foregroundStyle(grey)
          }
        }
        HStack(spacing: 14) {
          icon("ic_mentor_check", 24, Color(hex: 0xC7CBD1))
          Text("Approved — start taking calls").font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x9CA3AF))
        }
      }
      .padding(.top, 28)
      button("Refresh status", outline: true) { Task { await fetchStatus() } }.padding(.top, 28)
    }
    .padding(EdgeInsets(top: 32, leading: 24, bottom: 24, trailing: 24))
  }

  private var errorView: some View {
    VStack(spacing: 0) {
      icon("ic_mentor_error", 56, Color(hex: 0x9CA3AF))
      Text("Unable to fetch your mentor status. Please try again later.").font(.inter(15, .medium))
        .foregroundStyle(Color(hex: 0x4B5563)).multilineTextAlignment(.center).padding(.top, 14)
      button("Try again", outline: true) {
        status = .loading
        Task { await fetchStatus() }
      }
      .padding(.top, 24)
    }
    .padding(EdgeInsets(top: 80, leading: 32, bottom: 24, trailing: 32))
  }

  private static func join(_ separator: String, _ parts: [Any?]) -> String {
    parts.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      .joined(separator: separator)
  }

  private var approved: some View {
    let qualification = Self.join(" - ", [profile["speciality"], profile["designation"]])
    let place = Self.join(", ", [profile["institute_name"], profile["state"]])
    return VStack(alignment: .leading, spacing: 0) {
      card(padding: 16) {
        HStack(alignment: .top, spacing: 14) {
          NetImage(profile["image"] as? String, placeholder: "home_iv_user_profile").frame(width: 72, height: 72)
            .background(Color(hex: 0xEEF2F4)).clipShape(Circle())
          VStack(alignment: .leading, spacing: 0) {
            Text(profile.string("name") ?? "").font(.inter(18, .bold)).foregroundStyle(dark).lineLimit(1)
            if !qualification.isEmpty {
              Text(qualification).font(.inter(13, .medium)).foregroundStyle(AppColors.primary).padding(.top, 2)
            }
            if !place.isEmpty {
              HStack(alignment: .top, spacing: 6) {
                icon("ic_mentor_location", 14, AppColors.primary).padding(.top, 1)
                Text(place).font(.inter(12)).foregroundStyle(grey).lineSpacing(1.5)
              }
              .padding(.top, 6)
            }
          }
        }
        HStack(spacing: 6) {
          Image("ic_review_verified").resizable().frame(width: 16, height: 16)
          Text("Verified mentor").font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x13706B))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color(hex: 0xE0F7F3), in: Capsule())
      }

      HStack(spacing: 0) {
        HStack(spacing: 10) {
          Circle().fill(available ? Color(hex: 0x1E8E3E) : Color(hex: 0x9CA3AF)).frame(width: 10, height: 10)
          VStack(alignment: .leading, spacing: 2) {
            Text(available ? "Available for calls" : "Not available").font(.inter(15, .semibold)).foregroundStyle(dark)
            Text(available ? "Students can request video consultations with you" : "You won't receive consultation requests")
              .font(.inter(12)).foregroundStyle(grey)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        Toggle("", isOn: Binding(get: { available }, set: setAvailable))
          .labelsHidden().tint(AppColors.primary).disabled(savingAvailability)
          .accessibilityLabel("Available for calls")
      }
      .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 12))
      .background(.white, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE6ECEA)))
      .padding(.top, 12)

      Text("Session History").font(.inter(17, .bold)).foregroundStyle(dark).padding(.leading, 4).padding(.top, 24)
        .padding(.bottom, 10)
      LazyVStack(spacing: 0) {
        ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
          SessionRow(session: session).onAppear {
            if index >= sessions.count - 3, !loadingHistory, hasNext {
              page += 1
              loadingHistory = true
              Task { await fetchHistory() }
            }
          }
        }
      }
      if loadingHistory && sessions.isEmpty {
        ProgressView().tint(AppColors.primary).frame(maxWidth: .infinity).padding(.top, 6)
      }
      if historyLoaded && sessions.isEmpty && !loadingHistory {
        VStack(spacing: 0) {
          circle(56, Color(hex: 0xEEF2F4)) { icon("ic_mentor_video", 26, Color(hex: 0x9CA3AF)) }
          Text("No sessions yet").font(.inter(15, .semibold)).foregroundStyle(dark).padding(.top, 12)
          Text("Your consultation calls will show up here.").font(.inter(13)).foregroundStyle(grey)
            .multilineTextAlignment(.center).padding(.top, 4).padding(.horizontal, 24)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xE6ECEA)))
      }
    }
    .padding(EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16))
  }
}

/// item_counsellor_call_history.xml.
private struct SessionRow: View {
  let session: JSONObject

  private static func date(_ raw: String?) -> String {
    guard let raw else { return "" }
    let parse = DateFormatter()
    parse.locale = Locale(identifier: "en_US_POSIX")
    parse.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    guard let parsed = parse.date(from: String(raw.prefix(19))) else { return raw }
    let format = DateFormatter()
    format.dateFormat = "hh:mm a, dd MMM yyyy"
    return format.string(from: parsed)
  }

  private static func reason(_ reason: String?) -> String? {
    switch reason {
    case nil: nil
    case "user_hangup": "Ended by caller"
    case "counsellor_hangup": "Ended by you"
    case "rejected_by_counsellor": "You declined this call"
    case "disconnected": "Call disconnected"
    default: reason!.replacingOccurrences(of: "_", with: " ")
    }
  }

  var body: some View {
    let caller = session.object("caller")
    let charged = session.double("total_charged") ?? 0
    let amount =
      charged > 0 ? "₹\(charged == charged.rounded(.down) ? String(Int(charged)) : String(format: "%.2f", charged))" : "Free"
    let status = session.string("status") ?? ""
    let (bg, fg, label): (UInt32, UInt32, String) =
      switch status {
      case "ENDED": (0xE5F6E9, 0x1E8E3E, "Completed")
      case "REJECTED": (0xFDEAEA, 0xD32F2F, "Rejected")
      case "MISSED": (0xFFF3E0, 0xB26A00, "Missed")
      default: (0xEEEEEE, 0x666666, status)
      }
    let reason = Self.reason(session["end_reason"] as? String)
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        NetImage(caller?["image"] as? String, placeholder: "home_iv_mirror").frame(width: 48, height: 48).clipShape(Circle())
        VStack(alignment: .leading, spacing: 4) {
          Text(caller?.string("name") ?? "Unknown").font(.inter(15, .semibold)).foregroundStyle(.black)
          Text(Self.date((session["end_time"] as? String) ?? (session["start_time"] as? String))).font(.inter(12))
            .foregroundStyle(Color(hex: 0x8A8A8A))
        }
        Spacer(minLength: 8)
        Text(label).font(.inter(11, .semibold)).foregroundStyle(Color(hex: fg))
          .padding(.horizontal, 10).padding(.vertical, 4).background(Color(hex: bg), in: Capsule())
      }
      Rectangle().fill(Color(hex: 0xEDEDED)).frame(height: 1).padding(.vertical, 12)
      HStack(spacing: 0) {
        Text("⏱  ").font(.inter(13, .medium))
        Text(session.string("duration_formatted") ?? "").font(.inter(13, .semibold)).foregroundStyle(.black)
        Spacer()
        Text(amount).font(.inter(14, .bold)).foregroundStyle(Color(hex: 0x1E8E3E))
      }
      if let reason {
        Text(reason).font(.inter(11)).foregroundStyle(Color(hex: 0xB0B0B0)).padding(.top, 4)
      }
    }
    .padding(12)
    .background(.white, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE6ECEA)))
    .padding(.bottom, 10)
  }
}
