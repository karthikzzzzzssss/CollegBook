import SwiftUI
import WebKit

/// cutoff_page.dart AuthWebView: a server page loaded with the login's bearer
/// token; every main-frame navigation on the API host is re-issued with it
/// (WKWebView, like loadUrl(), sends no headers by itself).
struct AuthWebView: View {
  let url: URL
  var onError: (() -> Void)? = nil

  @State private var loading = true
  /// The load failed and no onError took it over: the default error view shows.
  @State private var failed = false

  var body: some View {
    if failed {
      VStack(spacing: 20) {
        Text("Couldn't load this page.").font(.inter(16, .bold)).foregroundStyle(AppColors.primary)
          .multilineTextAlignment(.center)
        FilterButton(label: "Retry", height: 48) {
          loading = true
          failed = false
        }
      }
      .padding(.horizontal, 32)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.white)
    } else {
      ZStack {
        AuthWebViewRepresentable(url: url, loading: $loading) {
          if let onError { onError() } else { failed = true }
        }
        if loading { ProgressView().tint(.black).controlSize(.large) }
      }
    }
  }
}

private struct AuthWebViewRepresentable: UIViewRepresentable {
  let url: URL
  @Binding var loading: Bool
  let onError: (() -> Void)?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> WKWebView {
    let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    web.navigationDelegate = context.coordinator
    web.uiDelegate = context.coordinator
    web.backgroundColor = .white
    web.isOpaque = false
    context.coordinator.source = url
    context.coordinator.load(url, in: web)
    return web
  }

  func updateUIView(_ web: WKWebView, context: Context) {
    context.coordinator.parent = self
    if context.coordinator.source != url {
      context.coordinator.source = url
      context.coordinator.load(url, in: web)
    }
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var parent: AuthWebViewRepresentable
    /// The URL last loaded with headers by us, let through once.
    private var authLoad: URL?
    /// The URL SwiftUI asked for. Links the page follows don't change it, so a
    /// redraw doesn't send the page back to where it started.
    fileprivate var source: URL?

    init(_ parent: AuthWebViewRepresentable) { self.parent = parent }

    func load(_ url: URL, in web: WKWebView) {
      authLoad = url
      var request = URLRequest(url: url)
      for (key, value) in APIClient.shared.authHeaders { request.setValue(value, forHTTPHeaderField: key) }
      web.load(request)
    }

    func webView(
      _ web: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = action.request.url else { return decisionHandler(.allow) }
      // tel:, mailto:, maps: and the like belong to their own apps; a web view
      // can only fail on them.
      if let scheme = url.scheme?.lowercased(), !["http", "https", "about", "data", "blob"].contains(scheme) {
        decisionHandler(.cancel)
        openOutside(url)
        return
      }
      // A link the user taps out of the server page (college website, Google
      // Maps) opens in Safari or its app, so Back still returns to the page.
      if action.navigationType == .linkActivated, action.targetFrame?.isMainFrame ?? true,
        url.host != APIClient.shared.apiHost
      {
        decisionHandler(.cancel)
        openOutside(url)
        return
      }
      guard action.targetFrame?.isMainFrame ?? true, url.host == APIClient.shared.apiHost
      else { return decisionHandler(.allow) }
      if url == authLoad || action.request.value(forHTTPHeaderField: "Authorization") != nil {
        return decisionHandler(.allow)
      }
      decisionHandler(.cancel)
      load(url, in: web)
    }

    /// target="_blank" links and window.open() (the website and "Open in
    /// Google Maps" links, the embedded map's own buttons): without this a web
    /// view silently drops them.
    func webView(
      _ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if let url = action.request.url {
        if url.host == APIClient.shared.apiHost { load(url, in: web) } else { openOutside(url) }
      }
      return nil
    }

    private func openOutside(_ url: URL) {
      DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    /// A server error page (401, 500…) counts as a failed load, not a page.
    func webView(
      _ web: WKWebView, decidePolicyFor response: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
        decisionHandler(.cancel)
        reportFailure()
        return
      }
      decisionHandler(.allow)
    }

    func webView(_ web: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      authLoad = nil
      parent.loading = true
    }

    func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) { parent.loading = false }

    func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      fail(error)
    }

    func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }

    private func fail(_ error: Error) {
      // A navigation we cancelled to re-issue with headers is not an error.
      if (error as NSError).code == NSURLErrorCancelled { return }
      reportFailure()
    }

    private func reportFailure() {
      parent.loading = false
      parent.onError?()
    }
  }
}

/// The header of the Fee Details and Choice List screens: the dark-green
/// gradient bar with back + title.
struct GreenHeader: View {
  let title: String
  var subtitle: String? = nil
  /// layout_choice_header (18pt title, 64pt min height) rather than the
  /// 16pt Fee Details bar.
  var large = false
  var onBack: (() -> Void)? = nil

  @Environment(\.dismiss) private var dismiss

  static let gradient = LinearGradient(
    colors: [Color(hex: 0x004D00), Color(hex: 0x003300), Color(hex: 0x003300)],
    startPoint: .top, endPoint: .bottom)

  var body: some View {
    HStack(spacing: large ? 8 : 16) {
      Button {
        if let onBack { onBack() } else { dismiss() }
      } label: {
        Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable()
          .frame(width: 22, height: 22).foregroundStyle(.white)
          .padding(large ? 9 : 0)
          .contentShape(Rectangle())
          .extendedTapArea(horizontal: large ? 2 : 11, vertical: large ? 2 : 11)
      }
      .accessibilityLabel("Back")
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.inter(large ? 18 : 16, .semibold)).foregroundStyle(.white).lineLimit(1)
        if let subtitle {
          Text(subtitle).font(.inter(13)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, large ? 6 : 16)
    .padding(.trailing, 16)
    .padding(.vertical, large ? 12 : 16)
    .frame(minHeight: large ? 64 : 0)
    .background(Self.gradient)
  }
}

/// FeeDetailsWebviewActivity: the green header over a server page.
struct GreenHeaderWebPage: View {
  let title: String
  let path: String

  var body: some View {
    VStack(spacing: 0) {
      GreenHeader(title: title)
      AuthWebView(url: APIClient.shared.url(path))
    }
    .background(Color.white)
    .background(GreenHeader.gradient.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
  }
}

/// CcmsItemWebviewActivity: a State / Course / Counselling card's page. The
/// item image stays fixed at the top while a white rounded sheet holding the
/// server's HTML (ccms/items/{id}/webview/) scrolls up over it.
struct CcmsItemPage: View {
  let itemId: Int
  let imageURL: String?

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var html: String?
  @State private var shown = false

  var body: some View {
    ZStack(alignment: .top) {
      NetImage(imageURL, placeholder: "home_iv_mirror")
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .clipped()
      if let html {
        HTMLView(html: html, baseURL: APIClient.shared.baseURL, onFinish: { shown = true })
          .opacity(shown ? 1 : 0)
      }
      if !shown {
        ProgressView().tint(Color(hex: 0x6750A4)).controlSize(.large).padding(.top, 274)
      }
      HStack {
        Button {
          dismiss()
        } label: {
          Image("ic_baseline_arrow_back_24").renderingMode(.template).resizable()
            .foregroundStyle(.black).padding(8)
            .frame(width: 40, height: 40)
            .background(.white, in: Circle())
        }
        .accessibilityLabel("Back")
        Spacer()
      }
      .padding(16)
    }
    .background(Color.white)
    .hiddenNavigationBar()
    .coversTabBar()
    .task { await load() }
  }

  private func load() async {
    do {
      let raw = try await app.api.text("ccms/items/\(itemId)/webview/")
      let body = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "<html><body><p>No content available.</p></body></html>" : raw
      html = Self.asSheet(body)
    } catch {
      // Left the page mid-request: nothing failed.
      guard !Task.isCancelled else { return }
      shown = true
      app.show("Failed to load content")
    }
  }

  /// Puts the page inside the native layout: a 236pt transparent gap (250pt
  /// image less the sheet's 14pt overlap), then a white sheet with 24pt top
  /// corners, a drag handle and 6pt side padding around the page itself.
  static func asSheet(_ html: String) -> String {
    let style = """
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        html, body.cb-host { background: transparent !important; margin: 0 !important; padding: 0 !important; }
        #cb-sheet { margin-top: 236px; background: #fff; border-radius: 24px 24px 0 0;
                    padding: 8px 6px 24px; min-height: 100vh; box-sizing: border-box; }
        #cb-handle { width: 40px; height: 4px; border-radius: 2px; background: #D0D0D0; margin: 0 auto; }
        #cb-page { margin-top: 10px; }
      </style>
      """
    let bodyOpen = try! NSRegularExpression(pattern: "<body([^>]*)>", options: .caseInsensitive)
    let ns = html as NSString
    guard let match = bodyOpen.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else {
      return "\(style)<body class=\"cb-host\"><div id=\"cb-sheet\"><div id=\"cb-handle\"></div><div id=\"cb-page\">\(html)</div></div></body>"
    }
    // The page's own body styles (background, font) move to the wrapper.
    let attrs = ns.substring(with: match.range(at: 1))
    let open = "<body class=\"cb-host\"><div id=\"cb-sheet\"><div id=\"cb-handle\"></div><div id=\"cb-page\" class=\"cb-body\"\(attrs)>"
    var out = ns.replacingCharacters(in: match.range, with: open)
    if let close = out.range(of: "</body>", options: .caseInsensitive) {
      out.replaceSubrange(close, with: "</div></div></body>")
    }
    // Rules written for "body" now style the page wrapper. Only inside <style>,
    // so the word "body," in the page's text is left alone.
    let bodyRule = try! NSRegularExpression(pattern: "(^|[\\s,}])body(\\s*[{,])", options: .anchorsMatchLines)
    let styleBlock = try! NSRegularExpression(pattern: "<style[^>]*>([\\s\\S]*?)</style>", options: .caseInsensitive)
    let rewritten = NSMutableString(string: out)
    for block in styleBlock.matches(in: out, range: NSRange(location: 0, length: rewritten.length)).reversed() {
      let css = rewritten.substring(with: block.range(at: 1))
      let rules = bodyRule.stringByReplacingMatches(
        in: css, range: NSRange(location: 0, length: (css as NSString).length), withTemplate: "$1.cb-body$2")
      rewritten.replaceCharacters(in: block.range(at: 1), with: rules)
    }
    out = rewritten as String
    if let head = out.range(of: "</head>", options: .caseInsensitive) {
      out.replaceSubrange(head, with: "\(style)</head>")
      return out
    }
    return style + out
  }
}

/// A transparent WKWebView showing an HTML string.
struct HTMLView: UIViewRepresentable {
  let html: String
  let baseURL: URL?
  var onFinish: (() -> Void)? = nil

  func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

  func makeUIView(context: Context) -> WKWebView {
    let web = WKWebView()
    web.isOpaque = false
    web.backgroundColor = .clear
    web.scrollView.backgroundColor = .clear
    web.scrollView.contentInsetAdjustmentBehavior = .never
    web.navigationDelegate = context.coordinator
    web.loadHTMLString(html, baseURL: baseURL)
    context.coordinator.loaded = html
    return web
  }

  func updateUIView(_ web: WKWebView, context: Context) {
    guard context.coordinator.loaded != html else { return }
    context.coordinator.loaded = html
    web.loadHTMLString(html, baseURL: baseURL)
  }

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let onFinish: (() -> Void)?
    var loaded: String?
    init(onFinish: (() -> Void)?) { self.onFinish = onFinish }

    func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }

    /// Links in the page open outside the app.
    func webView(
      _ web: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      if action.navigationType == .linkActivated, let url = action.request.url {
        UIApplication.shared.open(url)
        return decisionHandler(.cancel)
      }
      decisionHandler(.allow)
    }
  }
}
