import Foundation

struct ExamType: Identifiable, Hashable {
  let code: String
  let name: String
  let isSelected: Bool
  var id: String { code }
}

/// Every request the native fragment makes in setupInitialization(). Like
/// the native callbacks, a failed request just leaves its section empty, or
/// on a refresh as it was (a pull-to-refresh can be cancelled mid-request).
struct HomeData {
  var examTypes: [ExamType] = []
  var helpTools: [JSONObject] = []
  var news: [JSONObject] = []
  var reels: [JSONObject] = []
  var ccms: [JSONObject] = []
  var events: [JSONObject] = []
  var recommended: [JSONObject] = []
  var guidance: JSONObject = [:]

  static func load(_ api: APIClient, keeping previous: HomeData = HomeData()) async -> HomeData {
    async let examTypes = try? api.collection("exam-types/").items
    async let helpTools = try? api.collection("college/help-tools/").items
    async let news = try? api.collection("college/notifications/", query: ["page": "1", "limit": "40"]).items
    async let reels = try? api.collection("reels/landing-recommended-reels/").items
    async let ccms = try? api.collection("ccms/categories/").items
    async let events = try? api.collection("college/skill/", query: ["eventid": "all"]).items
    async let recommended = try? api.collection("college/recommended-colleges/").items
    async let guidance = try? api.object("college/guidance", query: ["tab": "guidance"])

    var data = HomeData()
    data.examTypes =
      (await examTypes)?.map {
        ExamType(code: $0.string("code") ?? "", name: $0.string("name") ?? "", isSelected: $0.bool("is_selected") == true)
      } ?? previous.examTypes
    data.helpTools = await helpTools ?? previous.helpTools
    data.news = await news ?? previous.news
    data.reels = await reels ?? previous.reels
    data.ccms = await ccms ?? previous.ccms
    data.events = await events ?? previous.events
    data.recommended = await recommended ?? previous.recommended
    data.guidance = await guidance ?? previous.guidance
    return data
  }
}

/// A review's title " – Dr. Aisha(AIR 7, 842)" split into name and meta.
struct Review: Identifiable {
  let id: Int
  let name: String
  let meta: String
  let stars: Int
  let description: String
  let image: String?

  init(id: Int, _ json: JSONObject) {
    self.id = id
    description = (json["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    image = json["image"] as? String
    var title = json["title"] as? String ?? ""
    var air: String?
    let pattern = try! NSRegularExpression(pattern: #"^(.*?)\s*\(([^)]*)\)\s*$"#)
    if let match = pattern.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
      let head = Range(match.range(at: 1), in: title), let inner = Range(match.range(at: 2), in: title)
    {
      var value = String(title[inner])
      value = value.replacingOccurrences(of: #"^AIR\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
      value = value.replacingOccurrences(of: #"\s*,\s*"#, with: ",", options: .regularExpression)
      air = value
      title = String(title[head])
    }
    name = title.replacingOccurrences(of: #"^[\s–—-]+"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    let degree = (json["degree"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let apiAir = (json["air"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let shownAir = apiAir.isEmpty ? air : apiAir
    meta = [degree.isEmpty ? nil : degree, (shownAir?.isEmpty == false) ? "AIR \(shownAir!)" : nil]
      .compactMap { $0 }.joined(separator: " • ")
    let rating = json.double("rating").map { Int($0.rounded()) } ?? 0
    stars = rating > 0 ? min(rating, 5) : 5
  }
}
