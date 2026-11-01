import SwiftUI

/// GroupChatFragment.SENDER_COLORS.
private let senderColors: [UInt32] = [0x1E4B3E, 0x0B6E99, 0x8E44AD, 0xC0392B, 0xD35400, 0x16A085, 0x2C3E50, 0xB7950B]

let removedText = "This message was removed"

enum BubbleType { case text, image, file, header }

/// The quote shown above a reply (ChatMessageModel.ReplyTo).
struct ReplyQuote {
  var preview: String
  var name: String?
  var targetId: String?
  var thumbnail: String?
}

/// One row of the chat list: a message bubble (one per attachment) or a
/// date header (ChatMessageModel).
final class ChatBubble: Identifiable {
  let type: BubbleType
  let id: Int
  let mine: Bool
  let username: String
  let time: String
  let at: Date?
  let senderColor: UInt32
  let dateLabel: String?

  var text: String?
  var reply: ReplyQuote?
  var attachmentId = 0
  var url: String?
  var fileName: String?
  var mimeType: String?
  var sizeText: String?
  var width: Double?
  var height: Double?

  /// Stable row identity: header by day, message by id and attachment.
  var rowId: String { type == .header ? "h:\(dateLabel ?? "")" : "m:\(id):\(attachmentId)" }
  var serverId: String { "\(id)" }
  var hasCaption: Bool { !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  init(header label: String) {
    type = .header
    id = 0
    mine = false
    username = ""
    time = ""
    at = nil
    senderColor = senderColors[0]
    dateLabel = label
  }

  init(type: BubbleType, id: Int, mine: Bool, username: String, time: String, at: Date?, senderColor: UInt32) {
    self.type = type
    self.id = id
    self.mine = mine
    self.username = username
    self.time = time
    self.at = at
    self.senderColor = senderColor
    dateLabel = nil
  }

  /// previewText(): the reply bar's label for this message.
  func previewText() -> String {
    switch type {
    case .image: hasCaption ? text! : "📷 Photo"
    case .file: "📎 \(fileName ?? "Document")"
    default: text ?? ""
    }
  }

  /// "48.5 KB  •  PDF".
  func fileInfoText() -> String {
    [sizeText?.trimmingCharacters(in: .whitespaces), typeLabel()].compactMap { $0 }.filter { !$0.isEmpty }
      .joined(separator: "  •  ")
  }

  private func typeLabel() -> String? {
    let mime = (mimeType ?? "").lowercased()
    if mime == "application/pdf" { return "PDF" }
    if mime.hasPrefix("image/") { return String(mime.dropFirst(6)).uppercased() }
    let name = (fileName ?? "").lowercased()
    guard let dot = name.lastIndex(of: "."), name.index(after: dot) < name.endIndex else { return nil }
    return String(name[name.index(after: dot)...]).uppercased()
  }
}

/// String.hashCode() of Java, so a sender keeps the native colour.
private func javaHash(_ s: String) -> Int32 {
  var h: Int32 = 0
  for unit in s.utf16 { h = h &* 31 &+ Int32(unit) }
  return h
}

private func luminance(_ rgb: UInt32) -> Double {
  func channel(_ v: UInt32) -> Double {
    let c = Double(v) / 255
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * channel((rgb >> 16) & 0xFF) + 0.7152 * channel((rgb >> 8) & 0xFF) + 0.0722 * channel(rgb & 0xFF)
}

/// GroupChatAdapter.readableOn(color, white): darkened until 4.5:1.
func readableOnWhite(_ rgb: UInt32) -> Color {
  var c = rgb
  var i = 0
  while i < 40, 1.05 / (luminance(c) + 0.05) < 4.5 {
    let r = UInt32(Double((c >> 16) & 0xFF) * 0.94)
    let g = UInt32(Double((c >> 8) & 0xFF) * 0.94)
    let b = UInt32(Double(c & 0xFF) * 0.94)
    c = (r << 16) | (g << 8) | b
    i += 1
  }
  return Color(hex: c)
}

func senderColorFor(_ username: String) -> UInt32 {
  senderColors[Int(abs(Int(javaHash(username)) % senderColors.count))]
}

/// parseIsoUtc: any fraction length, "Z" or "+05:30".
func parseChatTime(_ iso: String?) -> Date? {
  guard let iso else { return nil }
  let pattern = try! NSRegularExpression(
    pattern: #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})?$"#)
  guard let m = pattern.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) else { return nil }
  func part(_ i: Int) -> String? { Range(m.range(at: i), in: iso).map { String(iso[$0]) } }
  var parts = DateComponents()
  parts.timeZone = TimeZone(identifier: "UTC")
  parts.year = Int(part(1)!)
  parts.month = Int(part(2)!)
  parts.day = Int(part(3)!)
  parts.hour = Int(part(4)!)
  parts.minute = Int(part(5)!)
  parts.second = Int(part(6)!)
  guard var date = Calendar(identifier: .gregorian).date(from: parts) else { return nil }
  if let offset = part(7), offset != "Z" {
    let sign: Double = offset.hasPrefix("-") ? -1 : 1
    let hm = offset.dropFirst().split(separator: ":").compactMap { Double($0) }
    if hm.count == 2 { date = date.addingTimeInterval(-sign * (hm[0] * 3600 + hm[1] * 60)) }
  }
  return date
}

/// The device locale decides "pm" (en_IN) or "PM", as SimpleDateFormat does.
func formatChatTime(_ date: Date?, fallback: String) -> String {
  guard let date else { return fallback }
  let format = DateFormatter()
  format.dateFormat = "h:mm a"
  let s = format.string(from: date)
  return Locale.current.identifier.contains("_IN") ? s.lowercased() : s
}

private func dayKey(_ date: Date) -> String {
  let format = DateFormatter()
  format.dateFormat = "yyyyMMdd"
  return format.string(from: date)
}

/// WhatsApp wording: Today / Yesterday / weekday within the week / full date.
func dateLabelFor(_ date: Date?) -> String {
  guard let date else { return "" }
  let calendar = Calendar.current
  if calendar.isDateInToday(date) { return "Today" }
  if calendar.isDateInYesterday(date) { return "Yesterday" }
  let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date()))
    .day ?? 0
  let format = DateFormatter()
  format.dateFormat = (2...6).contains(days) ? "EEEE" : "d MMMM yyyy"
  return format.string(from: date)
}

func dayKeyOf(_ bubble: ChatBubble) -> String { bubble.at.map(dayKey) ?? "" }

private func text(_ m: JSONObject?, _ key: String) -> String? {
  guard let value = m?[key], !(value is NSNull) else { return nil }
  let s = (value as? String) ?? (value as? NSNumber)?.stringValue ?? "\(value)"
  return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
}

func formatFileSize(_ bytes: Double?) -> String? {
  guard let bytes, bytes > 0 else { return nil }
  if bytes < 1024 { return "\(Int(bytes)) B" }
  if bytes < 1024 * 1024 { return String(format: "%.1f KB", bytes / 1024) }
  return String(format: "%.1f MB", bytes / (1024 * 1024))
}

func guessMimeType(_ name: String?) -> String {
  let lower = (name ?? "").lowercased()
  if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
  if lower.hasSuffix(".png") { return "image/png" }
  if lower.hasSuffix(".gif") { return "image/gif" }
  if lower.hasSuffix(".webp") { return "image/webp" }
  if lower.hasSuffix(".heic") { return "image/heic" }
  if lower.hasSuffix(".pdf") { return "application/pdf" }
  return "application/octet-stream"
}

private func fileNameFromUrl(_ url: String) -> String {
  var name = String(url.split(separator: "/").last ?? "")
  if let q = name.firstIndex(of: "?") { name = String(name[..<q]) }
  return name
}

private func cleanName(_ s: String) -> String {
  s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

/// Parses server messages into bubbles (GroupChatFragment.parseChatMessage).
final class ChatParser {
  /// The signed-in user's chat name, learned from any is_mine message.
  var myUsername: String?
  /// Ids whose quotes read "This message was removed".
  var removedIds = Set<String>()

  func parse(_ obj: JSONObject) -> [ChatBubble] {
    let id = obj.int("id") ?? 0
    let message = text(obj, "message")
    let mine = obj.bool("is_mine") == true
    let username = cleanName(text(obj, "username") ?? "Member")
    if mine { myUsername = username }
    let iso = obj.string("created_at") ?? ""
    let at = parseChatTime(iso)
    let reply = parseReply(obj.object("reply_to"))
    func base(_ type: BubbleType) -> ChatBubble {
      ChatBubble(
        type: type, id: id, mine: mine, username: username, time: formatChatTime(at, fallback: iso), at: at,
        senderColor: senderColorFor(username))
    }
    var bubbles: [ChatBubble] = []
    for a in obj.objects("attachments") {
      guard let url = text(a, "url") else { continue }
      let name = text(a, "name") ?? fileNameFromUrl(url)
      let mime = text(a, "mime_type") ?? guessMimeType(name)
      let image = (a.string("file_type") ?? "").uppercased() == "IMAGE" || mime.hasPrefix("image/")
      let first = bubbles.isEmpty
      let b = base(image ? .image : .file)
      b.text = first ? message : nil
      b.reply = first ? reply : nil
      b.attachmentId = a.int("id") ?? 0
      b.url = url
      b.fileName = name
      b.mimeType = mime
      b.sizeText = formatFileSize(a.double("size"))
      b.width = a.double("width")
      b.height = a.double("height")
      bubbles.append(b)
    }
    if bubbles.isEmpty {
      let b = base(.text)
      b.text = message ?? ""
      b.reply = reply
      bubbles.append(b)
    }
    return bubbles
  }

  /// reply_to → "📷 Photo" / "📎 name" / its text / removed.
  func parseReply(_ r: JSONObject?) -> ReplyQuote? {
    guard let r else { return nil }
    let rid = r.int("id") ?? 0
    var name = text(r, "username").map(cleanName)
    if name != nil, name == myUsername { name = "You" }
    let target = rid > 0 ? "\(rid)" : nil
    if r.bool("is_removed") == true {
      if let target { removedIds.insert(target) }
      return ReplyQuote(preview: removedText, name: name, targetId: target)
    }
    let message = text(r, "message")
    let file = r.objects("attachments").first
    let image =
      file != nil
      && ((file?.string("file_type") ?? "").uppercased() == "IMAGE" || (file?.string("mime_type") ?? "").hasPrefix("image/"))
    let preview: String
    if let file, !image {
      preview = "📎 \(text(file, "name") ?? message ?? "Document")"
    } else if let message {
      preview = image ? "📷 \(message)" : message
    } else if file != nil {
      preview = "📷 Photo"
    } else {
      preview = r.bool("has_attachments") == true ? "📎 Attachment" : "Message"
    }
    return ReplyQuote(preview: preview, name: name, targetId: target, thumbnail: image ? text(file, "url") : nil)
  }

  /// A quote of an on-screen message, for replies to it once it's restored.
  static func quoteOf(_ bubbles: [ChatBubble]) -> ReplyQuote {
    let first = bubbles[0]
    return ReplyQuote(
      preview: first.type == .image && first.hasCaption ? "📷 \(first.text!)" : first.previewText(),
      name: first.mine ? "You" : first.username, targetId: first.serverId,
      thumbnail: first.type == .image ? first.url : nil)
  }
}

/// The event body under data / payload / message, or the event itself.
func eventPayload(_ event: JSONObject) -> JSONObject {
  for key in ["data", "payload", "message"] {
    if let o = event[key] as? JSONObject { return o }
  }
  return event
}

func messageObject(_ payload: JSONObject) -> JSONObject { payload["message"] as? JSONObject ?? payload }

func messageIdOf(_ payload: JSONObject) -> Int {
  if payload["message_id"] != nil { return payload.int("message_id") ?? 0 }
  return messageObject(payload).int("id") ?? 0
}

/// GroupChatFragment.sendErrorText.
func sendErrorText(_ http: Int, _ err: JSONObject?) -> String {
  let code = err?.string("message") ?? ""
  let data = err?.object("data")
  func opt(_ key: String, _ fallback: Int) -> Int { data?.int(key) ?? fallback }
  switch code {
  case "EMPTY_MESSAGE": return "Type a message or attach a file"
  case "MESSAGE_TOO_LONG": return "Message is too long (max \(opt("max_length", 1000)) characters)"
  case "TOO_MANY_FILES": return "You can attach up to \(opt("max_files", 10)) files"
  case "FILES_TOO_LARGE": return "Files must be 10 MB or smaller in total"
  case "INVALID_FILE_TYPE":
    if let name = data?.object("errors")?.objects("files").first.flatMap({ text($0, "name") }) {
      return "\(name) isn't a valid JPG, PNG or PDF"
    }
    return "Only JPG, PNG and PDF files can be sent"
  case "INVALID_REPLY": return "The message you replied to is no longer available"
  case "USER_BLOCKED_FROM_CHAT": return "You've been blocked from sending messages in this chat"
  case "GROUP_NOT_FOUND": return "This chat group isn't available"
  case "RATE_LIMITED":
    let seconds = opt("retry_after_seconds", 0)
    return seconds > 0 ? "You're sending too fast. Try again in \(seconds)s" : "You're sending too fast. Try again shortly"
  case "FILE_UPLOAD_FAILED": return "Upload failed. Please try again"
  case "TOKEN_EXPIRED", "AUTHENTICATION_FAILED": return "Your session has expired. Please log in again"
  case "PROFILE_INACTIVE": return "Your profile is deactivated"
  default: break
  }
  if http == 413 { return "Files must be 10 MB or smaller in total" }
  return text(err, "description") ?? "Couldn't send your message"
}
