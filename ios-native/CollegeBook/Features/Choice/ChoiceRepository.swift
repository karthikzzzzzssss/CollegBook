import UIKit

/// One choice list (college/collections/).
struct ChoiceList: Identifiable, Hashable {
  let id: String
  let name: String?
  let choiceCount: Int
  var choices: [ChoiceItem] = []

  static func == (a: ChoiceList, b: ChoiceList) -> Bool { a.id == b.id && a.choiceCount == b.choiceCount }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One entry of a list's data.items.
struct ChoiceItem: Identifiable {
  let id: String?
  var counselling: String?
  var institute: String?
  var state: String?
  var course: String?
  var beds = 0
  var quota: String?
  var category: String?
  var fee: String?
  var year: String?
}

/// One quota for the picked counselling + institute + course.
struct QuotaOption {
  let name: String
  let categories: [String]
}

/// A failure, already worded for the user.
struct ChoiceError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

/// The native ChoiceListRepository: lists, the add-choice drop-downs (cached
/// per selection), adding and removing choices.
@MainActor
final class ChoiceListRepository {
  static let shared = ChoiceListRepository()

  private let api = APIClient.shared
  private var lists: [ChoiceList] = []
  private var optionCache: [String: [String]] = [:]
  private var quotaCache: [String: [QuotaOption]] = [:]

  /// Logged out: the next user's lists and options start empty.
  func reset() {
    lists = []
    optionCache = [:]
    quotaCache = [:]
  }

  /// The server's message (a string, or the first field of an object
  /// message, else description), or "<fallback> (error <code>)".
  private static func message(_ error: Error, _ fallback: String) -> ChoiceError {
    if let error = error as? APIError {
      // Cancelled (its screen went away): no message, so no toast.
      if error.isCancelled { return ChoiceError(message: "") }
      if let body = error.payload {
        if let message = body["message"] as? String, !message.isEmpty { return ChoiceError(message: message) }
        if let message = body["message"] as? JSONObject {
          for value in message.values {
            if let s = value as? String { return ChoiceError(message: s) }
            if let list = value as? [Any], let first = list.first { return ChoiceError(message: "\(first)") }
          }
        }
        if let description = body.string("description") { return ChoiceError(message: description) }
      }
      if let code = error.statusCode { return ChoiceError(message: "\(fallback) (error \(code))") }
    }
    return ChoiceError(message: "\(fallback). Check your internet and try again.")
  }

  private static func strings(_ value: Any?) -> [String] {
    (value as? [Any] ?? []).compactMap { v in
      let s = (v as? String) ?? (v as? NSNumber)?.stringValue
      return s?.trimmingCharacters(in: .whitespaces).isEmpty == false ? s : nil
    }
  }

  /// GET college/collections/
  func getLists() async throws -> [ChoiceList] {
    do {
      let json = try await api.get("college/collections/")
      lists = (json["data"] as? [Any] ?? []).compactMap { $0 as? JSONObject }.map {
        ChoiceList(id: $0.string("id") ?? "", name: $0["name"] as? String, choiceCount: $0.int("total_items") ?? 0)
      }
      return lists
    } catch {
      throw Self.message(error, "Couldn't load your choice lists")
    }
  }

  /// Checked against the last fetched lists, before calling the server.
  func nameExists(_ name: String) -> Bool {
    let key = name.trimmingCharacters(in: .whitespaces).lowercased()
    return lists.contains { ($0.name ?? "").lowercased() == key }
  }

  /// POST college/collections/ {"name"}
  func createList(_ name: String) async throws -> ChoiceList {
    do {
      let json = try await api.request("POST", "college/collections/", body: ["name": name.trimmingCharacters(in: .whitespaces)])
      guard let data = json.object("data") else { throw APIError.invalid }
      let list = ChoiceList(id: data.string("id") ?? "", name: data["name"] as? String, choiceCount: data.int("total_items") ?? 0)
      lists.append(list)
      return list
    } catch {
      throw Self.message(error, "Couldn't create the list")
    }
  }

  private func fetchStrings(_ key: String, _ query: [String: String], _ endpoint: String, _ what: String) async throws
    -> [String]
  {
    if let cached = optionCache[key] { return cached }
    do {
      let json = try await api.get(endpoint, query: query)
      let results = Self.strings(json.object("data")?["results"])
      optionCache[key] = results
      return results
    } catch {
      throw Self.message(error, "Couldn't load \(what)")
    }
  }

  /// GET college/counselling-list/
  func counsellingOptions() async throws -> [String] {
    try await fetchStrings("counselling", [:], "college/counselling-list/", "counselling types")
  }

  /// GET college/choice/options/?counselling=
  func instituteOptions(_ counselling: String) async throws -> [String] {
    try await fetchStrings("institute|\(counselling)", ["counselling": counselling], "college/choice/options/", "institutes")
  }

  /// GET college/choice/options/?counselling=&institute=
  func courseOptions(_ counselling: String, _ institute: String) async throws -> [String] {
    try await fetchStrings(
      "course|\(counselling)|\(institute)", ["counselling": counselling, "institute": institute], "college/choice/options/",
      "courses")
  }

  /// GET college/choice/options/?counselling=&institute=&course=
  func quotaOptions(_ counselling: String, _ institute: String, _ course: String) async throws -> [QuotaOption] {
    let key = "\(counselling)|\(institute)|\(course)"
    if let cached = quotaCache[key] { return cached }
    do {
      let json = try await api.get(
        "college/choice/options/", query: ["counselling": counselling, "institute": institute, "course": course])
      let quotas = (json.object("data") ?? [:]).objects("quotas").compactMap { q in
        q.string("name").map { QuotaOption(name: $0, categories: Self.strings(q["categories"])) }
      }
      quotaCache[key] = quotas
      return quotas
    } catch {
      throw Self.message(error, "Couldn't load quotas")
    }
  }

  /// POST college/choice/
  func addChoice(listId: String, counselling: String, institute: String, course: String, quota: String, category: String)
    async throws
  {
    do {
      try await api.request(
        "POST", "college/choice/",
        body: [
          "collection_id": listId, "counselling": counselling, "institute": institute, "course": course, "quota": quota,
          "category": category,
        ])
    } catch {
      throw Self.message(error, "Couldn't add this choice")
    }
  }

  /// GET college/collections/{id}/ → the list and all its choices.
  func getChoices(_ listId: String) async throws -> ChoiceList {
    do {
      let json = try await api.get("college/collections/\(listId)/")
      let info = json.object("data") ?? [:]
      let raw = (json["data"] as? [Any]) ?? (info["items"] as? [Any]) ?? []
      func first(_ o: JSONObject, _ keys: [String]) -> String? { o.string(keys) }
      func firstInt(_ o: JSONObject, _ keys: [String]) -> Int { keys.lazy.compactMap { o.int($0) }.first ?? 0 }
      let choices = raw.compactMap { $0 as? JSONObject }.map { c in
        ChoiceItem(
          id: c.string("id"), counselling: first(c, ["counselling", "councelling_type"]),
          institute: first(c, ["institute", "college_name"]), state: first(c, ["state"]),
          course: first(c, ["course", "course_name"]), beds: firstInt(c, ["beds", "seats", "total_beds"]),
          quota: first(c, ["quota"]), category: first(c, ["category"]), fee: first(c, ["fee"]), year: first(c, ["year"]))
      }
      let cachedIndex = lists.firstIndex { $0.id == listId }
      let name = (info["name"] as? String) ?? cachedIndex.map { lists[$0].name } ?? nil
      let list = ChoiceList(id: listId, name: name, choiceCount: choices.count, choices: choices)
      if let cachedIndex { lists[cachedIndex] = list }
      return list
    } catch {
      throw Self.message(error, "Couldn't load this list")
    }
  }

  /// DELETE college/collections/{id}/
  func deleteList(_ listId: String) async throws {
    do {
      try await api.request("DELETE", "college/collections/\(listId)/")
      lists.removeAll { $0.id == listId }
    } catch {
      throw Self.message(error, "Couldn't delete this list")
    }
  }

  /// DELETE college/collections/{id}/items/{itemId}/
  func deleteChoice(_ listId: String, _ itemId: String) async throws {
    do {
      try await api.request("DELETE", "college/collections/\(listId)/items/\(itemId)/")
    } catch {
      throw Self.message(error, "Couldn't remove this choice")
    }
  }
}

// MARK: - Export (ChoiceListExporter)

enum ChoiceExportFormat {
  case pdf, csv

  var ext: String { self == .pdf ? "pdf" : "csv" }
  var label: String { self == .pdf ? "PDF" : "CSV" }
}

enum ChoiceExport {
  /// Writes the file to a temporary folder for the share sheet.
  static func export(_ list: ChoiceList, as format: ChoiceExportFormat) throws -> URL {
    let data = format == .pdf ? pdf(list) : csv(list)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(list.name, format))
    try data.write(to: url, options: .atomic)
    return url
  }

  private static func fileName(_ listName: String?, _ format: ChoiceExportFormat) -> String {
    var base = (listName ?? "").trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
    if base.isEmpty { base = "Choice_list" }
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyyMMdd_HHmm"
    return "\(base)_\(stamp.string(from: Date())).\(format.ext)"
  }

  private static func csv(_ list: ChoiceList) -> Data {
    var out = "\u{FEFF}"  // BOM so Excel reads the file as UTF-8
    func row(_ cells: [String?]) {
      out += cells.map { c in
        let v = c ?? ""
        return v.contains(",") || v.contains("\"") || v.contains("\n") ? "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\"" : v
      }.joined(separator: ",") + "\r\n"
    }
    row(["#", "Institute", "State", "Course", "Quota", "Category", "Fee", "Year"])
    for (i, c) in list.choices.enumerated() {
      row(["\(i + 1)", c.institute, c.state, c.course, c.quota, c.category, c.fee, c.year])
    }
    return Data(out.utf8)
  }

  // A4, 36pt margins, the native column widths and colours.
  private static let green = UIColor(red: 0, green: 0x33 / 255, blue: 0, alpha: 1)
  private static let text = UIColor(red: 0x12 / 255, green: 0x15 / 255, blue: 0x1B / 255, alpha: 1)
  private static let mutedText = UIColor(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255, alpha: 1)
  private static let border = UIColor(red: 0xE5 / 255, green: 0xE7 / 255, blue: 0xEB / 255, alpha: 1)
  private static let zebra = UIColor(red: 0xF6 / 255, green: 0xF8 / 255, blue: 0xF7 / 255, alpha: 1)
  private static let widths: [CGFloat] = [24, 170, 108, 82, 54, 52, 33]
  private static let header = ["#", "Institute", "Course", "Quota", "Category", "Fee", "Year"]

  private static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
    UIFont(name: bold ? "Inter-Bold" : "Inter-Regular", size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
  }

  private static func pdf(_ list: ChoiceList) -> Data {
    let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    let margin: CGFloat = 36
    let count = list.choices.count
    let date = DateFormatter()
    date.dateFormat = "d MMM yyyy, h:mm a"
    let renderer = UIGraphicsPDFRenderer(bounds: page)
    return renderer.pdfData { ctx in
      var pageNumber = 0
      var y: CGFloat = 0

      func draw(_ s: String, at point: CGPoint, width: CGFloat, size: CGFloat = 8.5, color: UIColor = text, bold: Bool = false)
        -> CGFloat
      {
        let attrs: [NSAttributedString.Key: Any] = [.font: font(size, bold: bold), .foregroundColor: color]
        let rect = (s as NSString).boundingRect(
          with: CGSize(width: width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, attributes: attrs,
          context: nil)
        (s as NSString).draw(with: CGRect(origin: point, size: rect.size), options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        return ceil(rect.height)
      }

      func newPage() {
        ctx.beginPage()
        pageNumber += 1
        y = margin
        if pageNumber == 1 {
          green.setFill()
          UIRectFill(CGRect(x: margin, y: y, width: 4, height: 40))
          _ = draw(list.name ?? "", at: CGPoint(x: margin + 14, y: y), width: page.width - 2 * margin - 14, size: 18, bold: true)
          _ = draw(
            "\(count) \(count == 1 ? "choice" : "choices")  ·  in order of preference  ·  Exported from CollegeBook on \(date.string(from: Date()))",
            at: CGPoint(x: margin + 14, y: y + 26), width: page.width - 2 * margin - 14, size: 9.5, color: mutedText)
          y += 58
        }
        let bar = UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: page.width - 2 * margin, height: 24), cornerRadius: 4)
        green.setFill()
        bar.fill()
        var x = margin
        for (i, title) in header.enumerated() {
          _ = draw(title, at: CGPoint(x: x + 6, y: y + 6.5), width: widths[i] - 12, color: .white, bold: true)
          x += widths[i]
        }
        y += 24
        _ = draw("CollegeBook", at: CGPoint(x: margin, y: page.height - margin + 8), width: 200, size: 9.5, color: mutedText)
        let label = "Page \(pageNumber)"
        let labelWidth = (label as NSString).size(withAttributes: [.font: font(9.5)]).width
        _ = draw(label, at: CGPoint(x: page.width - margin - labelWidth, y: page.height - margin + 8), width: 100, size: 9.5, color: mutedText)
      }

      newPage()
      if count == 0 { _ = draw("No choices in this list yet.", at: CGPoint(x: margin + 6, y: y + 6), width: 400) }
      for (i, c) in list.choices.enumerated() {
        let cells: [(String?, String?)] = [
          ("\(i + 1)", nil), (c.institute, c.state), (c.course, nil), (c.quota, nil), (c.category, nil),
          ((c.fee ?? "").isEmpty ? "" : "₹\(c.fee!)", nil), (c.year, nil),
        ]
        // Row height: the tallest cell.
        var height: CGFloat = 0
        for (index, cell) in cells.enumerated() {
          let w = widths[index] - 12
          var h = (cell.0 ?? "" as String).isEmpty ? 11 : (cell.0! as NSString).boundingRect(
            with: CGSize(width: w, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin,
            attributes: [.font: font(8.5)], context: nil
          ).height
          if let sub = cell.1, !sub.isEmpty {
            h += (sub as NSString).boundingRect(
              with: CGSize(width: w, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin,
              attributes: [.font: font(7.5)], context: nil
            ).height
          }
          height = max(height, ceil(h) + 12)
        }
        if y + height > page.height - margin - 4 { newPage() }
        if i % 2 == 1 {
          zebra.setFill()
          UIRectFill(CGRect(x: margin, y: y, width: page.width - 2 * margin, height: height))
        }
        var x = margin
        for (index, cell) in cells.enumerated() {
          let h = draw(cell.0 ?? "", at: CGPoint(x: x + 6, y: y + 6), width: widths[index] - 12)
          if let sub = cell.1, !sub.isEmpty {
            _ = draw(sub, at: CGPoint(x: x + 6, y: y + 6 + h), width: widths[index] - 12, size: 7.5, color: mutedText)
          }
          x += widths[index]
        }
        border.setFill()
        UIRectFill(CGRect(x: margin, y: y + height - 0.7, width: page.width - 2 * margin, height: 0.7))
        y += height
      }
    }
  }
}
