import SwiftUI

private let chatBg = Color(hex: 0xF2EDE4)
private let textDark = Color(hex: 0x1C1E21)
private let meta = Color(hex: 0x6B7280)
private let sheetText = Color(hex: 0x1B2B26)
private let pageSize = 40

/// The tag list of the native "Select Tags" screen.
let askTags = [
  "All india", "Andhra Pradesh", "Arunachal Pradesh", "Assam", "Bihar", "Chhattisgarh", "Goa", "Gujarat", "Haryana",
  "Himachal Pradesh", "Jharkhand", "Karnataka", "Kerala", "Madhya Pradesh", "Maharashtra", "Manipur", "Meghalaya",
  "Mizoram", "Nagaland", "Odisha", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana", "Tripura",
  "Uttar Pradesh", "Uttarakhand", "West Bengal", "Andaman and Nicobar Islands", "Chandigarh",
  "Dadra and Nagar Haveli and Daman and Diu", "Lakshadweep", "Delhi", "Puducherry", "Ladakh", "Jammu and Kashmir",
]

/// The picked tags ("All india,Telangana") as the API files them: All India
/// is "AIC", so the question lists under All India as well as the state.
func apiTags(_ tags: String) -> String {
  tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    .map { $0.lowercased() == "all india" ? "AIC" : $0 }.joined(separator: ",")
}

/// Html.fromHtml(...).toString() for the plain titles/answers the API sends.
private func plain(_ html: String?) -> String {
  var s = (html ?? "").replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
  s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  for (entity, value) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
    s = s.replacingOccurrences(of: entity, with: value)
  }
  return s.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespaces)
}

private func cleanName(_ name: String?) -> String {
  (name ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

struct QnaItem: Identifiable {
  let id: Int
  let title: String
  let name: String
  let date: String?
  let tags: [String]
  let totalComment: Int
  let answers: [(id: Int, text: String, name: String)]

  init(_ json: JSONObject) {
    id = json.int("id") ?? 0
    title = plain(json["title"] as? String)
    name = cleanName(json["name"] as? String)
    date = json["create_date"] as? String
    tags = json.strings("tags_array")
    totalComment = json.int("total_comment") ?? 0
    answers = json.objects("comments").compactMap {
      let text = plain($0["comment"] as? String)
      return text.isEmpty ? nil : ($0.int("id") ?? 0, text, cleanName($0["name"] as? String))
    }
  }
}

/// One Q&A page (CollegeQandAFragment): "All India" or a state.
struct QnaListView: View {
  let selection: String
  /// Bumped by the parent to reload (a question was posted or answered).
  let refreshToken: Int
  let onAsk: () -> Void
  /// An answer was posted: a question tagged All India and a state is in
  /// both lists, so the page reloads both.
  let onAnswered: () -> Void

  @EnvironmentObject private var app: AppState
  @ObservedObject private var moderation = Moderation.shared
  @State private var items: [QnaItem] = []
  @State private var page = 1
  @State private var lastPage = false
  @State private var loading = false
  @State private var loaded = false
  @State private var failed = false
  @State private var opened: QnaItem?
  /// Bumped by a refresh: answers to anything older are dropped.
  @State private var loadGeneration = 0

  var body: some View {
    let empty = loaded && !loading && items.isEmpty
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          Color.clear.frame(height: 4).id("top")
          ForEach(items) { item in
            Group {
              if moderation.isHidden("question:\(item.id)", by: item.name) {
                // Kept as a sliver so reaching the end still loads the next page.
                Color.clear.frame(height: 1)
              } else {
                QuestionCard(item: item) { opened = item }
              }
            }
            .onAppear { if item.id == items.last?.id { Task { await load() } } }
          }
        }
        .padding(.bottom, 108)
      }
      .pullToRefresh { await load(refresh: true) }
      .overlay {
        if empty && failed {
          Text("Couldn't load discussions. Check your internet and pull down to try again.").font(.inter(15))
            .foregroundStyle(stateGreen).multilineTextAlignment(.center).padding(.horizontal, 32)
        } else if empty {
          EmptyQnaState(onStart: onAsk)
        }
        if loading && items.isEmpty { ProgressView().tint(stateGreen).controlSize(.large) }
      }
      .onChangeCompat(of: refreshToken) { _, _ in
        proxy.scrollTo("top", anchor: .top)
        Task { await load(refresh: true) }
      }
      .onChangeCompat(of: selection) { _, _ in
        items = []
        Task { await load(refresh: true) }
      }
    }
    .background(chatBg)
    .task { if !loaded { await load() } }
    .sheet(item: $opened) { item in
      AnswersSheet(item: item) { answered in if answered { onAnswered() } }
    }
  }

  private func load(refresh: Bool = false) async {
    if !refresh, loading || lastPage { return }
    if refresh { loadGeneration += 1 }
    let generation = loadGeneration
    let target = refresh ? 1 : page
    let allIndia = selection == "All India"
    loading = true
    failed = false
    defer { if generation == loadGeneration { loading = false } }
    do {
      let json = try await app.api.get(
        "college/homepage",
        query: [
          "page": "\(target)", "limit": "\(pageSize)", "state": allIndia ? "" : selection,
          "councelling_type": allIndia ? "AIC" : "SC", "query": "user-post",
        ])
      guard generation == loadGeneration else { return }
      let data = json.object("data") ?? [:]
      lastPage = target >= (data.int("total_page") ?? 1)
      var seen: Set<Int> = refresh ? [] : Set(items.map(\.id))
      // The API accepts blank questions; they'd show as empty cards.
      let fresh = data.objects("results").map(QnaItem.init).filter { !$0.title.isEmpty && seen.insert($0.id).inserted }
      // A refresh replaces the list only now: a failed one keeps what's shown.
      items = refresh ? fresh : items + fresh
      page = target + 1
      loaded = true
    } catch {
      guard generation == loadGeneration else { return }
      // An empty list says so instead of "No discussions yet"; pull to retry.
      loaded = true
      failed = true
      if !items.isEmpty { app.show(refresh ? "Couldn't refresh discussions" : "Couldn't load more discussions") }
    }
  }
}

private struct EmptyQnaState: View {
  let onStart: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Image("ic_forum_outline").renderingMode(.template).resizable().foregroundStyle(stateGreen).padding(20)
        .frame(width: 72, height: 72).background(AppColors.allIndia, in: Circle())
      Text("No discussions yet").font(.inter(18, .bold)).foregroundStyle(textDark).padding(.top, 16)
      Text("Ask about cutoffs, colleges or counselling rounds and get answers from students who've been there.")
        .font(.inter(13, .medium)).foregroundStyle(meta).multilineTextAlignment(.center).lineSpacing(4).padding(.top, 6)
      Button(action: onStart) {
        HStack(spacing: 6) {
          Image("ic_edit_pencil_small").renderingMode(.template).resizable().frame(width: 16, height: 16)
          Text("Start a discussion").font(.inter(13, .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(stateGreen, in: RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
      .padding(.top, 20)
    }
    .padding(.horizontal, 32)
  }
}

/// row_college_qanda.xml.
private struct QuestionCard: View {
  let item: QnaItem
  let onOpen: () -> Void
  @ObservedObject private var moderation = Moderation.shared

  var body: some View {
    let poster = item.name.isEmpty ? "Guest" : item.name
    let count = max(item.totalComment, item.answers.count)
    let answers = item.answers.filter { !moderation.isHidden("answer:\($0.id)", by: $0.name) }
    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Text(String(poster.prefix(1)).uppercased()).font(.inter(14, .bold)).foregroundStyle(stateGreen)
            .frame(width: 34, height: 34).background(AppColors.allIndia, in: Circle())
          VStack(alignment: .leading, spacing: 0) {
            Text(poster).font(.inter(13, .bold)).foregroundStyle(textDark).lineLimit(1)
            if let date = item.date, !date.isEmpty {
              Text(date).font(.inter(11, .medium)).foregroundStyle(meta).lineLimit(1)
            }
          }
          Spacer(minLength: 0)
          // Room for the ••• menu laid over the card.
          Color.clear.frame(width: 30, height: 1)
        }
        .padding(.horizontal, 14)
        Text(item.title).font(.inter(16, .bold)).foregroundStyle(textDark).lineSpacing(5)
          .multilineTextAlignment(.leading)
          .padding(EdgeInsets(top: 10, leading: 14, bottom: 0, trailing: 14))
        if !answers.isEmpty { AnswerCards(question: item.title, answers: answers).padding(.top, 12) }
        Rectangle().fill(Color(hex: 0xEEEAE2)).frame(height: 1).padding(.top, 12)
        HStack(spacing: 6) {
          Image("ic_comment_outline_small").renderingMode(.template).resizable().frame(width: 16, height: 16)
            .foregroundStyle(meta)
          Text(count == 0 ? "No answers yet" : count == 1 ? "1 answer" : "\(count) answers").font(.inter(12, .medium))
            .foregroundStyle(meta)
          Spacer()
          HStack(spacing: 6) {
            Image("ic_edit_pencil_small").renderingMode(.template).resizable().frame(width: 16, height: 16)
            Text("Answer").font(.inter(12, .bold))
          }
          .foregroundStyle(stateGreen)
          .padding(.horizontal, 14).frame(height: 32)
          .background(AppColors.allIndia, in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
      }
      .padding(.top, 14)
      .background(.white, in: RoundedRectangle(cornerRadius: 12))
      .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
    }
    .buttonStyle(.plain)
    // Over the card, not inside its button, so it takes its own taps.
    .overlay(alignment: .topTrailing) {
      ModerationMenu(content: "question:\(item.id)", kind: "question", author: item.name, text: item.title)
        .padding(.top, 6).padding(.trailing, 4)
    }
    .padding(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
  }
}

/// QnAAnswerCardAdapter: a lone answer spans the row; several show 1.5 cards
/// so the next one peeks in. "... Read More" opens the full answer.
private struct AnswerCards: View {
  let question: String
  let answers: [(id: Int, text: String, name: String)]

  @State private var detail: Int?

  var body: some View {
    // The question card spans the screen less its 12pt margins.
    let available = UIScreen.main.bounds.width - 24 - 28
    let alone = answers.count == 1
    let cardWidth = alone ? available : (available - 8 * 0.5) / 1.5
    Group {
      if alone {
        card(0, width: cardWidth, alone: true).padding(.horizontal, 14)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 8) {
            ForEach(answers.indices, id: \.self) { card($0, width: cardWidth, alone: false) }
          }
          .padding(.horizontal, 14)
        }
      }
    }
    .sheet(item: $detail) { index in
      AnswerDetailSheet(question: question, answer: answers[index])
    }
  }

  private func card(_ index: Int, width: CGFloat, alone: Bool) -> some View {
    let answer = answers[index]
    return Button {
      detail = index
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(answer.name.isEmpty ? " " : "Answer by \(answer.name)").font(.inter(10, .medium)).foregroundStyle(meta)
          .lineLimit(1).opacity(answer.name.isEmpty ? 0 : 1)
        ReadMoreText(text: answer.text, width: width - 26, maxLines: 3)
          .frame(minHeight: alone ? nil : 3 * 13 * 1.37, alignment: .top)
      }
      .padding(12)
      .frame(width: width, alignment: .topLeading)
      .background(Color(hex: 0xF3FBEA), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xDDEFC9)))
    }
    .buttonStyle(.plain)
  }
}

extension Int: @retroactive Identifiable {
  public var id: Int { self }
}

/// InlineReadMore: three lines, the last ending in "... Read More".
private struct ReadMoreText: View {
  let text: String
  let width: CGFloat
  let maxLines: Int

  private static let font = UIFont(name: "Inter-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)

  var body: some View {
    Text(shown).font(.inter(13, .medium)).foregroundStyle(.black).lineSpacing(13 * 0.37).lineLimit(maxLines)
      .multilineTextAlignment(.leading)
  }

  private var shown: AttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 13 * 0.37
    let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .paragraphStyle: paragraph]
    func lines(_ s: String) -> Int {
      let h = (s as NSString).boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attrs,
        context: nil
      ).height
      return Int((h + paragraph.lineSpacing) / (Self.font.lineHeight + paragraph.lineSpacing) + 0.01)
    }
    if lines(text) <= maxLines { return AttributedString(text) }
    var lo = 0
    var hi = text.count
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if lines(String(text.prefix(mid)).trimmingCharacters(in: .whitespaces) + "... Read More") <= maxLines {
        lo = mid
      } else {
        hi = mid - 1
      }
    }
    var more = AttributedString("Read More")
    more.foregroundColor = Color(hex: 0x003300)
    more.font = .inter(13, .bold)
    return AttributedString(String(text.prefix(lo)).trimmingCharacters(in: .whitespaces) + "... ") + more
  }
}

/// bottom_sheet_news_detail.xml with the question and the full answer.
private struct AnswerDetailSheet: View {
  let question: String
  let answer: (id: Int, text: String, name: String)
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text(answer.name).font(.inter(13, .medium)).foregroundStyle(meta)
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark").foregroundStyle(meta).padding(12)
          }
          .accessibilityLabel("Close")
        }
        Text(question).font(.inter(18, .bold)).foregroundStyle(textDark).lineSpacing(5)
        Text(answer.text).font(.inter(15)).foregroundStyle(Color(hex: 0x3C4043)).lineSpacing(6).padding(.top, 12)
      }
      .padding(EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20))
    }
    .sheetDetents([.medium, .large])
    .sheetDragIndicatorVisible()
    .sheetCornerRadius(28)
  }
}

// MARK: - Answers sheet (bottomsheet_qna_layout.xml)

private final class Answer: Identifiable {
  let id: Int
  let text: String
  var liked: Bool
  var unliked: Bool

  init(_ json: JSONObject) {
    id = json.int("id") ?? 0
    text = json.string("comment") ?? ""
    liked = json.object("status")?.bool("like_status") == true
    unliked = json.object("status")?.bool("unlike_status") == true
  }
}

/// The question, its answers with up/down votes, and a "Write answer" bar.
struct AnswersSheet: View {
  let item: QnaItem
  let onClose: (Bool) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var moderation = Moderation.shared
  @State private var answers: [Answer]?
  @State private var loadFailed = false
  @State private var input = ""
  @State private var posting = false
  @State private var answered = false
  @State private var revision = 0
  @FocusState private var focused: Bool

  private var tags: String {
    item.tags.compactMap { tag -> String? in
      var t = tag.trimmingCharacters(in: .whitespaces)
      if t.hasPrefix("@") { t.removeFirst() }
      if t.isEmpty { return nil }
      return t.uppercased() == "AIC" ? "All India" : t
    }.joined(separator: "  ·  ")
  }

  var body: some View {
    let count = answers?.count ?? 0
    VStack(spacing: 0) {
      HStack {
        Text("Question & Answers").font(.inter(16, .bold)).foregroundStyle(sheetText)
        Spacer()
        ModerationMenu(content: "question:\(item.id)", kind: "question", author: item.name, text: item.title) {
          dismiss()
        }
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_close").renderingMode(.template).resizable().foregroundStyle(Color(hex: 0x5C6B66)).padding(9)
            .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Close")
      }
      .padding(.leading, 16).padding(.trailing, 10).padding(.top, 14)
      .frame(height: 60)
      .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE3ECE8)).frame(height: 1) }

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 0) {
            Text(item.title).font(.inter(17, .bold)).foregroundStyle(sheetText).lineSpacing(7)
            if !tags.isEmpty {
              Text(tags).font(.inter(12, .semibold)).foregroundStyle(AppColors.primary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: 0xE6F2ED), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 10)
            }
          }
          .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.white)
          Rectangle().fill(Color(hex: 0xE3ECE8)).frame(height: 1)
          Text(answers == nil ? (loadFailed ? "COULDN'T LOAD ANSWERS" : "ANSWERS") : count == 0 ? "NO ANSWERS YET" : count == 1 ? "1 ANSWER" : "\(count) ANSWERS")
            .font(.inter(12, .semibold)).kerning(0.72).foregroundStyle(meta)
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16))
          ForEach(answers ?? []) { answer in
            if !moderation.isHidden("answer:\(answer.id)", by: author(of: answer)) { answerRow(answer) }
          }
        }
        .padding(.bottom, 12)
        .id(revision)
      }
      .background(Color(hex: 0xF6FAF7))

      HStack(spacing: 10) {
        Image("home_iv_user_profile").resizable().scaledToFill().frame(width: 30, height: 30).clipShape(Circle())
        MultilineTextField($input, prompt: Text("Write answer").foregroundColor(Color(hex: 0x8A9A94)), lines: 1...5)
          .font(.inter(14.5)).foregroundStyle(sheetText)
          .textInputAutocapitalization(.sentences)
          .focused($focused)
        if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Button(action: post) {
            Image("ic_baseline_send_24").renderingMode(.template).resizable().foregroundStyle(.white).padding(9)
              .frame(width: 36, height: 36).background(AppColors.primary, in: Circle())
          }
          .buttonStyle(.plain)
          .disabled(posting)
          .accessibilityLabel("Send answer")
        }
      }
      .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 6))
      .frame(minHeight: 48)
      .background(Color(hex: 0xF3F7F5), in: RoundedRectangle(cornerRadius: 24))
      .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(hex: 0xDCE9E3)))
      .padding(.horizontal, 12).padding(.vertical, 10)
      .background(.white)
      .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xE3ECE8)).frame(height: 1) }
    }
    .background(.white)
    .sheetDetents([.large])
    .sheetDragIndicatorVisible()
    .sheetCornerRadius(24)
    .task {
      await load()
      // The native sheet opens with the keyboard up on "Write answer".
      try? await Task.sleep(seconds: 0.2)
      focused = true
    }
    .onDisappear { onClose(answered) }
  }

  /// article_comments_row.xml.
  /// The answers here come without names; the question's preview has them.
  private func author(of answer: Answer) -> String {
    item.answers.first { $0.id == answer.id }?.name ?? ""
  }

  private func answerRow(_ answer: Answer) -> some View {
    let on = AppColors.primary
    let off = Color(hex: 0x455A64)
    return VStack(alignment: .leading, spacing: 8) {
      Text(answer.text).font(.inter(14.5)).foregroundStyle(sheetText).lineSpacing(6)
      HStack(spacing: 8) {
        Button {
          react(answer, "like")
        } label: {
          HStack(spacing: 6) {
            Image("ic_baseline_thumb_up_24").renderingMode(.template).resizable().frame(width: 16, height: 16)
            Text("Upvote").font(.inter(12.5, .semibold))
          }
          .foregroundStyle(answer.liked ? on : off)
          .frame(height: 32)
          .padding(.trailing, 8)
        }
        .buttonStyle(.plain)
        Button {
          react(answer, "unlike")
        } label: {
          Image("ic_baseline_thumb_down_24").renderingMode(.template).resizable().frame(width: 16, height: 16)
            .foregroundStyle(answer.unliked ? on : off).padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Downvote")
        Spacer(minLength: 0)
        ModerationMenu(content: "answer:\(answer.id)", kind: "answer", author: author(of: answer), text: answer.text)
          .padding(.trailing, -10)
      }
    }
    .padding(EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE1ECE7)))
    .padding(.horizontal, 16).padding(.vertical, 5)
  }

  private func load() async {
    do {
      let data = try await app.api.object("college/question-comments/\(item.id)/")
      answers = data.objects("results").map(Answer.init)
      loadFailed = false
    } catch {
      // Not "No answers yet": they just couldn't be fetched.
      loadFailed = true
    }
  }

  private func post() {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !posting else { return }
    posting = true
    Task {
      defer { posting = false }
      do {
        try await app.api.request("POST", "college/question-comments/\(item.id)/", body: ["comment": text])
        answered = true
        input = ""
        focused = false
        await load()
      } catch {
        // The answer stays in the box to try again.
        app.show((error as? APIError)?.payload == nil ? "Network failure, please try again." : error.localizedDescription)
      }
    }
  }

  /// college/question-comments-reaction/ {comment_id, action}.
  private func react(_ answer: Answer, _ action: String) {
    Task {
      guard
        let data = try? await app.api.request(
          "POST", "college/question-comments-reaction/", body: ["comment_id": answer.id, "action": action]
        ).object("data")
      else { return }
      let liked = data.bool("like_status") == true
      let unliked = data.bool("unlike_status") == true
      if action == "like" {
        answer.liked = liked
        if liked { answer.unliked = false }
      } else {
        answer.unliked = unliked
        if unliked { answer.liked = false } else if liked { answer.liked = true }
      }
      revision += 1
    }
  }
}

// MARK: - Ask a Question (CollegeQnAPostActivity)

struct AskQuestionView: View {
  /// The posted tags.
  let onPosted: (String) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var tags: String?
  @State private var pickingTags = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 0) {
      AskHeader(title: "Ask a Question") {
        Button(action: post) {
          Text("Post").font(.inter(14, .bold)).foregroundStyle(.white)
            .padding(.horizontal, 22).frame(height: 36)
            .background(AppColors.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
      }
      MultilineTextField($title, prompt: Text("Type your question...").foregroundColor(Color(hex: 0x8A9A94)))
        .font(.inter(15, .medium)).foregroundStyle(sheetText).lineSpacing(6)
        .textInputAutocapitalization(.sentences)
        .focused($focused)
        .padding(16)
        .frame(height: 180, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? AppColors.primary : Color(hex: 0xDCE9E3), lineWidth: focused ? 1.5 : 1))
        .padding(EdgeInsets(top: 20, leading: 16, bottom: 0, trailing: 16))
      Button {
        pickingTags = true
      } label: {
        HStack(spacing: 8) {
          Text(tags.map { $0.replacingOccurrences(of: ",", with: ", ") } ?? "Select Tags...").font(.inter(15, .semibold))
            .foregroundStyle(tags == nil ? Color(hex: 0x8A9A94) : AppColors.primary).lineLimit(1)
          Spacer()
          Image("ic_baseline_keyboard_arrow_down_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
            .foregroundStyle(AppColors.primary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xDCE9E3)))
      }
      .buttonStyle(.plain)
      .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
      Spacer()
    }
    .background(Color(hex: 0xF6FAF7))
    .background(Color.white.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
    .contentShape(Rectangle())
    .onTapGesture { focused = false }
    .compatDestination(isPresented: $pickingTags) {
      SelectTagsView(selected: tags) { tags = $0 }
    }
  }

  private func post() {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return app.show("Please write question") }
    guard let tags else { return app.show("Please select tags") }
    let hide = NativeAlert.progress()
    Task {
      do {
        let json = try await app.api.request("POST", "college/homepage", body: ["title": trimmed, "tags": apiTags(tags)])
        hide()
        app.show(json.string("message") ?? "No message found")
        onPosted(tags)
        dismiss()
      } catch {
        hide()
        app.show((error as? APIError)?.payload == nil ? "Network failure, please try again." : error.localizedDescription)
      }
    }
  }
}

/// The white 56pt header with back + title (bg_ask_header).
private struct AskHeader<Trailing: View>: View {
  let title: String
  @ViewBuilder var trailing: Trailing
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    HStack(spacing: 8) {
      Button {
        dismiss()
      } label: {
        Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
          .foregroundStyle(sheetText).padding(8)
      }
      .accessibilityLabel("Back")
      Text(title).font(.inter(18, .bold)).foregroundStyle(sheetText).lineLimit(1)
      Spacer()
      trailing
    }
    .padding(.leading, 8)
    .frame(height: 56)
    .background(.white)
    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xE3ECE8)).frame(height: 1) }
  }
}

/// BigDoctorPickDataActivity for tags: up to two chips, then "Done".
private struct SelectTagsView: View {
  let selected: String?
  let onDone: (String) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var picked: [String] = []
  /// Like the native screen, Done only knows about taps made here.
  @State private var result: String?
  private static let max = 2

  var body: some View {
    VStack(spacing: 0) {
      AskHeader(title: "Select Tags") { EmptyView() }
      ScrollView {
        FlowStack(spacing: 8, lineSpacing: 8) {
          ForEach(askTags, id: \.self) { tag in
            let on = picked.contains(tag)
            Button {
              toggle(tag)
            } label: {
              Text(tag).font(.inter(13.5, .semibold)).foregroundStyle(on ? .white : Color(hex: 0x2B3A35))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(on ? AppColors.primary : .white, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : Color(hex: 0xD6E3DE)))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
          }
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
      }
      .background(Color(hex: 0xF6FAF7))
      Button {
        guard let result, !result.trimmingCharacters(in: .whitespaces).isEmpty else {
          return app.show("Please Select Tags")
        }
        onDone(result)
        dismiss()
      } label: {
        Text("Done").font(.inter(15, .bold)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
          .background(AppColors.primary, in: Capsule())
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 16).padding(.vertical, 12)
    }
    .background(Color.white)
    .hiddenNavigationBar()
    .coversTabBar()
    .onAppear {
      picked = Array((selected ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }.prefix(Self.max))
    }
  }

  private func toggle(_ tag: String) {
    if let index = picked.firstIndex(of: tag) {
      picked.remove(at: index)
    } else {
      guard picked.count < Self.max else { return app.show("You can select up to \(Self.max) only") }
      picked.append(tag)
    }
    result = picked.joined(separator: ",")
  }
}
