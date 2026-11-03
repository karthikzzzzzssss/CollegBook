import SwiftUI

/// Guideline 1.2 for the Community chat and Q&A: anyone can report a post or
/// block the person who wrote it. Both act on this phone at once: a reported
/// post, and everything from a blocked person, is hidden. There is no report
/// API, so a report also goes to support on WhatsApp, who act on it within 24
/// hours (Terms: Community rules).
@MainActor
final class Moderation: ObservableObject {
  static let shared = Moderation()

  @Published private(set) var blocked: Set<String> = []
  @Published private(set) var reported: Set<String> = []
  private var account = ""

  private init() { reload() }

  /// The signed-in account's lists: each account keeps its own.
  func reload() {
    account = SessionStore.shared.profile.phone ?? ""
    blocked = Set(UserDefaults.standard.stringArray(forKey: key("blocked")) ?? [])
    reported = Set(UserDefaults.standard.stringArray(forKey: key("reported")) ?? [])
  }

  /// `content` names the post ("chat:12", "question:4", "answer:57").
  func isHidden(_ content: String, by author: String) -> Bool {
    reported.contains(content) || blocked.contains(Self.person(author))
  }

  /// A named poster can be blocked; "Guest" and blank names are everyone's.
  static func canBlock(_ author: String) -> Bool {
    let name = person(author)
    return !name.isEmpty && name != "guest"
  }

  /// Asks first, then hides the post and sends it to support. True if reported.
  @discardableResult
  func report(_ content: String, kind: String, by author: String, text: String) async -> Bool {
    // Let a context menu finish closing, or the alert has nothing to show on.
    try? await Task.sleep(seconds: 0.4)
    let confirmed = await NativeAlert.show(
      title: "Report this \(kind)?",
      message: "It will be hidden for you, and the CollegeBook team will review it within 24 hours.",
      negative: "Cancel", positive: "Report", destructive: true)
    guard confirmed else { return false }
    reported.insert(content)
    save()
    let excerpt = text.count > 300 ? "\(text.prefix(300))…" : text
    let message = """
      Report from CollegeBook: \(kind) \(content) by \(author.isEmpty ? "unknown" : author)
      "\(excerpt)"
      Reason:\u{20}
      """
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    Platform.open("https://wa.me/91\(supportPhone)?text=\(message.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")")
    return true
  }

  /// Asks first; then nothing from that person shows here. True if blocked.
  @discardableResult
  func block(_ author: String) async -> Bool {
    guard Self.canBlock(author) else { return false }
    try? await Task.sleep(seconds: 0.4)
    let confirmed = await NativeAlert.show(
      title: "Block \(author)?", message: "You won't see their messages, questions or answers any more.",
      negative: "Cancel", positive: "Block", destructive: true)
    guard confirmed else { return false }
    blocked.insert(Self.person(author))
    save()
    return true
  }

  private func save() {
    UserDefaults.standard.set(Array(blocked), forKey: key("blocked"))
    UserDefaults.standard.set(Array(reported), forKey: key("reported"))
  }

  private func key(_ list: String) -> String { "collegebook.moderation.\(list).\(account)" }

  private static func person(_ name: String) -> String { name.trimmingCharacters(in: .whitespaces).lowercased() }
}

/// Report and Block for one post, as a ••• button.
struct ModerationMenu: View {
  let content: String
  let kind: String
  let author: String
  let text: String
  var tint = Color(hex: 0x6B7280)
  /// After a report or block: the post is gone.
  var onHidden: () -> Void = {}

  var body: some View {
    Menu {
      Button {
        Task { if await Moderation.shared.report(content, kind: kind, by: author, text: text) { onHidden() } }
      } label: {
        Label("Report \(kind)", systemImage: "exclamationmark.bubble")
      }
      if Moderation.canBlock(author) {
        Button(role: .destructive) {
          Task { if await Moderation.shared.block(author) { onHidden() } }
        } label: {
          Label("Block \(author)", systemImage: "hand.raised")
        }
      }
    } label: {
      Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .accessibilityLabel("More options for this \(kind)")
  }
}
