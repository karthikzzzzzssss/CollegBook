import Foundation

/// CollegeGuideApiConfig: the dev server in Debug builds, production in
/// Release; `COLLEGE_GUIDE_API_BASE_URL` (scheme environment or Info.plist)
/// overrides either.
enum APIConfig {
  static let baseURL: URL = {
    let configured =
      ProcessInfo.processInfo.environment["COLLEGE_GUIDE_API_BASE_URL"]
      ?? Bundle.main.object(forInfoDictionaryKey: "COLLEGE_GUIDE_API_BASE_URL") as? String
    if let configured, !configured.isEmpty, let url = URL(string: configured) { return url }
    #if DEBUG
      return URL(string: "https://dev.collegebook.app/api/v1/")!
    #else
      return URL(string: "https://api.collegebook.app/api/v1/")!
    #endif
  }()
}

struct APIError: LocalizedError {
  let message: String
  var statusCode: Int? = nil
  var payload: JSONObject? = nil

  var errorDescription: String? { message }

  static let offline = APIError(message: "Could not connect. Check your internet connection and try again.")
  static let timeout = APIError(message: "The server took too long to respond. Please try again.")
  static let invalid = APIError(message: "The CollegeBook service returned an invalid response.")
  /// The request was cancelled (its screen went away): nothing to tell the
  /// user, so no message.
  static let cancelled = APIError(message: "")

  var isCancelled: Bool { message.isEmpty && statusCode == nil }
}

extension Notification.Name {
  /// The refresh token was rejected; the app goes back to the login screen.
  static let sessionExpired = Notification.Name("CollegeBookSessionExpired")
}

/// CollegeGuideCollection: `data.results`, `data` as a list, or `results`.
struct APICollection {
  let items: [JSONObject]
  let raw: JSONObject
  /// `data` when it is an object (pages, totals, default parameters).
  let pagination: JSONObject?

  init(_ json: JSONObject) throws {
    let data = json["data"]
    let dataMap = data as? JSONObject
    guard let results = (dataMap?["results"] ?? (data as? [Any]) ?? json["results"]) as? [Any] else {
      throw APIError(message: "The CollegeBook service returned an invalid list response.")
    }
    items = results.compactMap { $0 as? JSONObject }
    raw = json
    pagination = dataMap
  }
}

/// lib/features/home/college_guide_api.dart: bearer-authenticated JSON calls
/// that refresh an expired access token once and retry.
final class APIClient: @unchecked Sendable {
  static let shared = APIClient()

  let baseURL: URL
  private let session: URLSession
  private let store: SessionStore
  private let refresher = TokenRefresher()
  /// Before iOS 17, URL(string:) refuses spaces and non-ASCII instead of
  /// encoding them; "%" stays so an encoded string isn't encoded twice.
  private static let urlCharacters = CharacterSet.urlQueryAllowed.union(.urlPathAllowed)
    .union(CharacterSet(charactersIn: "%#"))

  init(baseURL: URL = APIConfig.baseURL, store: SessionStore = .shared) {
    self.baseURL = baseURL
    self.store = store
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    session = URLSession(configuration: config)
  }

  var apiHost: String { baseURL.host ?? "" }
  var accessToken: String? { store.accessToken }

  func url(_ endpoint: String, query: [String: String] = [:]) -> URL {
    let encoded = endpoint.addingPercentEncoding(withAllowedCharacters: Self.urlCharacters) ?? endpoint
    let resolved = URL(string: encoded, relativeTo: baseURL)?.absoluteURL ?? baseURL
    guard !query.isEmpty, var parts = URLComponents(url: resolved, resolvingAgainstBaseURL: false)
    else { return resolved }
    // Added to any query the endpoint already has.
    parts.queryItems = (parts.queryItems ?? []) + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    // URLQueryItem leaves "+", which servers read as a space.
    parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return parts.url ?? resolved
  }

  /// A media path from the API made absolute against the API's origin.
  func mediaURL(_ path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    let encoded = path.addingPercentEncoding(withAllowedCharacters: Self.urlCharacters) ?? path
    if let url = URL(string: encoded), url.scheme != nil { return url }
    return URL(string: encoded.hasPrefix("/") ? encoded : "/\(encoded)", relativeTo: baseURL)?.absoluteURL
  }

  // MARK: Requests

  func get(_ endpoint: String, query: [String: String] = [:]) async throws -> JSONObject {
    try await request("GET", endpoint, query: query)
  }

  func collection(_ endpoint: String, query: [String: String] = [:]) async throws -> APICollection {
    try APICollection(await get(endpoint, query: query))
  }

  func postCollection(_ endpoint: String, body: JSONObject) async throws -> APICollection {
    try APICollection(await request("POST", endpoint, body: body))
  }

  /// `data` when it is an object, else the whole body.
  func object(_ endpoint: String, query: [String: String] = [:]) async throws -> JSONObject {
    let json = try await get(endpoint, query: query)
    if let data = json["data"] as? JSONObject { return data }
    if json["data"] == nil || json["data"] is NSNull { return json }
    throw APIError(message: "The CollegeBook service returned an invalid object response.")
  }

  @discardableResult
  func request(
    _ method: String, _ endpoint: String, query: [String: String] = [:], body: JSONObject? = nil
  ) async throws -> JSONObject {
    let target = url(endpoint, query: query)
    let (data, response) = try await authorized { try await self.send(method, target, token: $0, body: body) }
    return try decode(data, response)
  }

  /// The raw body of an endpoint that answers HTML.
  func text(_ endpoint: String) async throws -> String {
    let target = url(endpoint)
    let (data, response) = try await authorized { try await self.send("GET", target, token: $0, body: nil) }
    guard (200..<300).contains(response.statusCode) else {
      throw APIError(message: "Failed to load content", statusCode: response.statusCode)
    }
    return String(decoding: data, as: UTF8.self)
  }

  struct UploadFile {
    let field: String
    let data: Data
    let fileName: String
    let mimeType: String
  }

  /// A multipart POST (the chat's text + files). Answers the HTTP status and
  /// the decoded JSON body, if any — the chat reads its own error codes.
  func postMultipart(
    _ endpoint: String, method: String = "POST", fields: [String: String], file: UploadFile?
  ) async throws -> (
    status: Int, json: JSONObject?
  ) {
    func attempt(_ token: String?) async throws -> (Data, HTTPURLResponse) {
      let boundary = "Boundary-\(UUID().uuidString)"
      var body = Data()
      func line(_ s: String) { body.append(Data((s + "\r\n").utf8)) }
      for (key, value) in fields {
        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"\(key)\"")
        line("")
        line(value)
      }
      if let file {
        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.fileName)\"")
        line("Content-Type: \(file.mimeType)")
        line("")
        body.append(file.data)
        line("")
      }
      line("--\(boundary)--")
      var request = URLRequest(url: url(endpoint))
      request.httpMethod = method
      request.timeoutInterval = 90
      request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
      if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
      do {
        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalid }
        return (data, http)
      } catch let error as URLError {
        throw Self.mapped(error)
      }
    }
    let (data, response) = try await authorized(attempt)
    return (response.statusCode, (try? JSONSerialization.jsonObject(with: data)) as? JSONObject)
  }

  /// Bearer headers for a WebView request.
  var authHeaders: [String: String] {
    guard let token = store.accessToken, !token.isEmpty else { return [:] }
    return ["Authorization": "Bearer \(token)"]
  }

  private func send(_ method: String, _ url: URL, token: String?, body: JSONObject?) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw APIError.invalid }
      return (data, http)
    } catch let error as URLError {
      throw Self.mapped(error)
    }
  }

  /// Makes a call with the saved token. If the server refuses it, refreshes
  /// once and repeats the call. A refused refresh ends the session; one that
  /// merely failed (offline, timeout, 5xx) throws and keeps the session.
  private func authorized(
    _ attempt: (String?) async throws -> (Data, HTTPURLResponse)
  ) async throws -> (Data, HTTPURLResponse) {
    let generation = store.generation
    let token = store.accessToken
    let first = try await attempt(token)
    // After a logout the refused call isn't repeated, least of all as whoever
    // logged in since.
    guard let token, first.1.statusCode >= 400, Self.isTokenRejected(first.0), store.generation == generation else {
      return first
    }
    if let current = store.accessToken, current != token {
      return try await attempt(current)  // another call already refreshed it
    }
    let refreshed: String
    do {
      refreshed = try await refresher.refresh { try await self.refreshAccessToken() }
    } catch let error as APIError where Self.isRefreshRefused(error) {
      if store.clear(ifGeneration: generation) {
        await MainActor.run { NotificationCenter.default.post(name: .sessionExpired, object: nil) }
      }
      return first
    }
    return try await attempt(refreshed)
  }

  /// The server answered and said no; 408 and 429 only mean try again later.
  /// No status means the refresh never got an answer it could read.
  private static func isRefreshRefused(_ error: APIError) -> Bool {
    guard let status = error.statusCode, status < 500 else { return false }
    return status != 408 && status != 429
  }

  /// The server refused the access token: expired, or one it doesn't know
  /// (TOKEN_INVALID, e.g. issued by another server). Either way the refresh
  /// token is tried, and if that fails too the user logs in again; before,
  /// an invalid token left every screen empty with no way back to login.
  private static func isTokenRejected(_ data: Data) -> Bool {
    let body = String(decoding: data, as: UTF8.self)
    return body.contains("TOKEN_EXPIRED") || body.contains("TOKEN_INVALID")
  }

  /// A cancelled request (its screen went away, or a refresh was cancelled)
  /// is not a network failure: no "offline" message for it.
  private static func mapped(_ error: URLError) -> Error {
    switch error.code {
    case .cancelled: APIError.cancelled
    case .timedOut: APIError.timeout
    default: APIError.offline
    }
  }

  private func decode(_ data: Data, _ response: HTTPURLResponse) throws -> JSONObject {
    let ok = (200..<300).contains(response.statusCode)
    // A DELETE may answer 204 with no body at all.
    if ok, data.isEmpty || String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return [:]
    }
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else { throw APIError.invalid }
    if !ok || (json["status"] as? Bool) == false {
      let message =
        json.string(["description", "detail", "message"]) ?? "The CollegeBook request failed. Please try again."
      throw APIError(message: message, statusCode: response.statusCode, payload: json)
    }
    return json
  }

  private func refreshAccessToken() async throws -> String {
    let generation = store.generation
    guard let refresh = store.refreshToken, !refresh.isEmpty else {
      throw APIError(message: "No refresh token.", statusCode: 401)
    }
    let (data, response) = try await send("POST", url("auth/token/refresh/"), token: nil, body: ["refresh": refresh])
    let json = try decode(data, response)
    guard let access = json.object("data")?.string("access") else {
      throw APIError(message: "The session refresh response did not contain an access token.")
    }
    let saved = store.saveRefreshedTokens(
      access: access, refresh: json.object("data")?.string("refresh") ?? refresh, generation: generation)
    // Logged out while this ran: the session stays ended.
    guard saved else { throw APIError.cancelled }
    return access
  }
}

/// One refresh at a time: concurrent expired calls share its result.
private actor TokenRefresher {
  private var pending: Task<String, Error>?

  func refresh(_ work: @escaping @Sendable () async throws -> String) async throws -> String {
    if let pending { return try await pending.value }
    let task = Task { try await work() }
    pending = task
    defer { pending = nil }
    return try await task.value
  }
}
