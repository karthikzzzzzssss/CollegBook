import PDFKit
import SwiftUI

private let sentColor = Color(hex: 0xDCF8C6)
let chatTimeColor = Color(hex: 0x606B72)
private let quoteBg = Color(hex: 0xF5F5F5)
private let quoteBar = Color(hex: 0x28328C)
let quoteName = Color(hex: 0x167D28)

/// incoming/outgoing_speech_bubble.xml: a 4pt rounded body inset from the
/// tail side and a tail at the top corner.
struct SpeechBubbleShape: Shape {
  let incoming: Bool

  func path(in rect: CGRect) -> Path {
    let w = rect.width
    let h = rect.height
    var path = Path()
    if incoming {
      path.addRoundedRect(in: CGRect(x: 8, y: 0, width: w - 8, height: h), cornerSize: CGSize(width: 4, height: 4))
      path.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 34.9, y: 0), CGPoint(x: 11.5, y: 16.4)])
    } else {
      path.addRoundedRect(in: CGRect(x: 0, y: 0, width: w - 10, height: h), cornerSize: CGSize(width: 4, height: 4))
      path.addLines([CGPoint(x: w, y: 0), CGPoint(x: w - 12.9, y: 15.3), CGPoint(x: w - 31.1, y: 0)])
    }
    path.closeSubpath()
    return path
  }
}

/// applyBubbleShape: first in a run → speech bubble with tail (content padded
/// on the tail side); later ones → a plain 8pt card lined up under it.
struct BubbleShell<Content: View>: View {
  let incoming: Bool
  let first: Bool
  @ViewBuilder let content: Content

  var body: some View {
    let fill = incoming ? Color.white : sentColor
    Group {
      if first {
        content
          .padding(.leading, incoming ? 8 : 0)
          .padding(.trailing, incoming ? 0 : 10)
          .background {
            SpeechBubbleShape(incoming: incoming).fill(fill)
              .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
          }
      } else {
        content
          .background(fill, in: RoundedRectangle(cornerRadius: 8))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
          .padding(.leading, incoming ? 8 : 0)
          .padding(.trailing, incoming ? 0 : 10)
      }
    }
  }
}

/// The message with blank room at its end for the overlaid time, so the time
/// sits on the last line when it fits and drops below when it doesn't.
struct TextWithTime: View {
  let text: String
  let time: String
  var startMargin: CGFloat = 5
  var endMargin: CGFloat = 6

  var body: some View {
    (Text(text).font(.inter(16, .medium)).foregroundColor(.black)
      + Text("  \(time)").font(.inter(11)).foregroundColor(.clear))
      .padding(.leading, startMargin)
      .padding(.trailing, endMargin)
      .overlay(alignment: .bottomTrailing) {
        Text(time).font(.inter(11)).foregroundStyle(chatTimeColor)
      }
  }
}

/// The reply preview text with "📷 " drawn as an outlined photo icon.
struct ReplyPreviewText: View {
  let text: String
  var size: CGFloat = 13
  var color: Color = .black
  var lines = 1

  var body: some View {
    let prefix = "📷 "
    Group {
      if text.hasPrefix(prefix) {
        (Text(Image("ic_reply_photo").renderingMode(.template)) + Text(" \(text.dropFirst(prefix.count))"))
      } else {
        Text(text)
      }
    }
    .font(.inter(size, .medium))
    .foregroundStyle(color)
    .lineLimit(lines)
  }
}

/// The quote box inside a bubble.
struct QuoteBox: View {
  let quote: ReplyQuote
  let onTap: () -> Void
  /// Media / file bubbles use the one-line quote with a small thumbnail.
  let compact: Bool

  var body: some View {
    let texts = VStack(alignment: .leading, spacing: 3) {
      Text(quote.name ?? "").font(.inter(13, .medium)).foregroundStyle(quoteName).lineLimit(1)
      ReplyPreviewText(text: quote.preview, lines: compact ? 1 : 3).frame(minWidth: 80, alignment: .leading)
    }
    Button(action: onTap) {
      Group {
        if compact {
          HStack(spacing: 8) {
            RoundedCornersShape(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(quoteBar).frame(width: 5, height: 36)
            texts
            Spacer(minLength: 0)
            if let thumb = quote.thumbnail {
              NetImage(thumb).frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
            }
          }
          .padding(6)
        } else {
          HStack(spacing: 0) {
            RoundedCornersShape(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(quoteBar).frame(width: 5)
            texts.padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 10))
            Spacer(minLength: 0)
            if let thumb = quote.thumbnail {
              NetImage(thumb).frame(width: 56).frame(minHeight: 56).clipped()
            }
          }
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .background(quoteBg)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .padding(.bottom, 4)
  }
}

struct SenderName: View {
  let bubble: ChatBubble
  var body: some View {
    Text(bubble.username).font(.inter(13, .medium)).foregroundStyle(readableOnWhite(bubble.senderColor)).lineLimit(1)
  }
}

/// The sender's initial on a circle in their colour.
struct ChatAvatar: View {
  let bubble: ChatBubble
  let visible: Bool

  var body: some View {
    let name = bubble.username.trimmingCharacters(in: .whitespaces)
    Text(name.first.map { String($0).uppercased() } ?? "?").font(.inter(13, .bold)).foregroundStyle(.white)
      .frame(width: 28, height: 28)
      .background(readableOnWhite(bubble.senderColor), in: Circle())
      .opacity(visible ? 1 : 0)
  }
}

/// group_item_chat_{send,receive}_text.xml.
struct TextBubbleView: View {
  let bubble: ChatBubble
  let first: Bool
  let maxWidth: CGFloat
  let onQuoteTap: () -> Void

  var body: some View {
    let incoming = !bubble.mine
    BubbleShell(incoming: incoming, first: first) {
      VStack(alignment: .leading, spacing: 0) {
        if incoming && first { SenderName(bubble: bubble).padding(EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 8)) }
        if let quote = bubble.reply, !quote.preview.isEmpty {
          QuoteBox(quote: quote, onTap: onQuoteTap, compact: false).frame(maxWidth: maxWidth + 15, alignment: .leading)
        }
        TextWithTime(text: bubble.text ?? "", time: bubble.time).padding(2)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: maxWidth + 20, alignment: .leading)
      .padding(EdgeInsets(top: incoming ? 3 : 4, leading: 6, bottom: 6, trailing: 6))
    }
  }
}

/// group_item_chat_{send,receive}_media.xml.
struct ImageBubbleView: View {
  let bubble: ChatBubble
  let first: Bool
  let maxWidth: CGFloat
  let onQuoteTap: () -> Void
  let onImageTap: () -> Void

  var body: some View {
    let incoming = !bubble.mine
    let width = maxWidth - 4
    // Height follows the photo's ratio, clamped to 160–340pt; unknown → 4:3.
    let height = min(max(width * (bubble.height ?? 3) / (bubble.width ?? 4), 160), 340)
    BubbleShell(incoming: incoming, first: first) {
      VStack(alignment: .leading, spacing: 0) {
        if let quote = bubble.reply, !quote.preview.isEmpty {
          QuoteBox(quote: quote, onTap: onQuoteTap, compact: true).padding(EdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 6))
        }
        if incoming && first { SenderName(bubble: bubble).padding(EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6)) }
        NetImage(bubble.url)
          .frame(width: width, height: height)
          .background(.white)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(alignment: .bottomTrailing) {
            if !bubble.hasCaption {
              Text(bubble.time).font(.inter(11)).foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
          }
          .onTapGesture(perform: onImageTap)
          .padding(2)
        if bubble.hasCaption {
          TextWithTime(text: bubble.text!, time: bubble.time, startMargin: 0, endMargin: 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 4, leading: 11, bottom: 6, trailing: 6))
        }
      }
      .frame(width: maxWidth)
    }
  }
}

/// Page-1 top-strip previews of chat PDFs (PdfThumbnailLoader).
@MainActor
enum PdfThumbs {
  private static var cache: [String: UIImage] = [:]
  private static var failed = Set<String>()

  static func load(_ url: String) async -> UIImage? {
    if let hit = cache[url] { return hit }
    if failed.contains(url) { return nil }
    guard let remote = URL(string: url), let (data, _) = try? await URLSession.shared.data(from: remote),
      data.count <= 15 * 1024 * 1024, let page = PDFDocument(data: data)?.page(at: 0)
    else {
      // Scrolled away mid-download isn't a bad file: it loads next time.
      if !Task.isCancelled { failed.insert(url) }
      return nil
    }
    let bounds = page.bounds(for: .mediaBox)
    let image = page.thumbnail(of: CGSize(width: 720, height: 720 * bounds.height / max(bounds.width, 1)), for: .mediaBox)
    cache[url] = image
    return image
  }
}

/// group_item_chat_{send,receive}_file.xml.
struct FileBubbleView: View {
  let bubble: ChatBubble
  let first: Bool
  let maxWidth: CGFloat
  let onQuoteTap: () -> Void
  let onOpen: () -> Void

  @State private var thumb: UIImage?

  var body: some View {
    let incoming = !bubble.mine
    let pdf = (bubble.mimeType ?? "").lowercased() == "application/pdf"
    BubbleShell(incoming: incoming, first: first) {
      VStack(alignment: .leading, spacing: 0) {
        if let quote = bubble.reply, !quote.preview.isEmpty { QuoteBox(quote: quote, onTap: onQuoteTap, compact: true) }
        if incoming && first { SenderName(bubble: bubble).padding(.leading, 5).padding(.bottom, 2) }
        Button(action: onOpen) {
          VStack(alignment: .leading, spacing: 0) {
            ZStack {
              if let thumb {
                // Page 1's top strip, centre-cropped into the preview box.
                Image(uiImage: thumb).resizable().scaledToFill().frame(height: 85, alignment: .top).clipped()
              } else {
                RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xB4B4BE), lineWidth: 0.8)
                Image("ic_document").renderingMode(.template).resizable().frame(width: 24, height: 24)
                  .foregroundStyle(Color(hex: 0x4CAF50))
              }
            }
            .frame(maxWidth: .infinity).frame(height: 85)
            .background(.white, in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(bubble.fileName ?? "Document").font(.inter(16, .medium)).foregroundStyle(.black)
              .lineLimit(1).truncationMode(.middle)
              .padding(EdgeInsets(top: 8, leading: 8, bottom: 0, trailing: 8))
            HStack {
              Text(bubble.fileInfoText()).font(.inter(12)).foregroundStyle(chatTimeColor)
              Spacer()
              // With no caption the time sits on the size line itself.
              if !bubble.hasCaption { Text(bubble.time).font(.inter(11)).foregroundStyle(chatTimeColor) }
            }
            .padding(.leading, 8).padding(.trailing, 6).padding(.top, 2).padding(.bottom, bubble.hasCaption ? 0 : 3)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if bubble.hasCaption {
          TextWithTime(text: bubble.text!, time: bubble.time, startMargin: 0, endMargin: 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 3, trailing: 6))
        }
      }
      .padding(3)
      .frame(width: maxWidth - (first ? (incoming ? 8 : 10) : 0))
    }
    .task(id: bubble.url) {
      if pdf, let url = bubble.url { thumb = await PdfThumbs.load(url) }
    }
  }
}

/// group_item_date_header.xml.
struct DateHeaderChip: View {
  let label: String
  var sticky = false

  var body: some View {
    Text(label).font(.inter(12.5, .medium)).foregroundStyle(sticky ? .white : chatTimeColor)
      .padding(.horizontal, 12).padding(.vertical, sticky ? 6 : 4)
      .background(sticky ? Color(hex: 0x3B3B3B) : .white, in: RoundedRectangle(cornerRadius: 10))
      .shadow(color: .black.opacity(sticky ? 0 : 0.12), radius: 0.5, y: 0.5)
  }
}
