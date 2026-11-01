import SwiftUI

/// Glide / CachedNetworkImage: a remote image, memory- and disk-cached, with
/// a bundled placeholder while loading and on failure.
struct NetImage: View {
  let url: URL?
  var placeholder: String? = nil
  var contentMode: ContentMode = .fill

  @State private var image: UIImage?

  init(_ url: URL?, placeholder: String? = nil, contentMode: ContentMode = .fill) {
    self.url = url
    self.placeholder = placeholder
    self.contentMode = contentMode
    _image = State(initialValue: url.flatMap { ImageCache.shared.cached($0) })
  }

  init(_ string: String?, placeholder: String? = nil, contentMode: ContentMode = .fill) {
    self.init(APIClient.shared.mediaURL(string), placeholder: placeholder, contentMode: contentMode)
  }

  var body: some View {
    // Takes exactly the space offered and crops inside it: a filled image
    // never widens its parent.
    Color.clear
      .overlay {
        if let image {
          Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else if let placeholder {
          Image(placeholder).resizable().aspectRatio(contentMode: contentMode)
        }
      }
      .clipped()
      .task(id: url) {
      // @State outlives a change of URL: nothing of the old image may stay.
      guard let url else {
        image = nil
        return
      }
      if let hit = ImageCache.shared.cached(url) {
        image = hit
        return
      }
      image = nil
      let loaded = await ImageCache.shared.load(url)
      if !Task.isCancelled { image = loaded }
    }
  }
}

final class ImageCache: @unchecked Sendable {
  static let shared = ImageCache()

  private let memory = NSCache<NSURL, UIImage>()
  private let session: URLSession

  private init() {
    memory.countLimit = 300
    let config = URLSessionConfiguration.default
    config.urlCache = URLCache(memoryCapacity: 20 << 20, diskCapacity: 300 << 20)
    config.requestCachePolicy = .returnCacheDataElseLoad
    session = URLSession(configuration: config)
  }

  func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

  func load(_ url: URL) async -> UIImage? {
    if let hit = cached(url) { return hit }
    guard let (data, _) = try? await session.data(from: url),
      let decoded = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data)
    else { return nil }
    memory.setObject(decoded, forKey: url as NSURL)
    return decoded
  }
}
