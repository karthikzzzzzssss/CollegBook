import Foundation
import os

private let authLog = Logger(subsystem: "com.minibrain.collegetutor", category: "auth")

/// AuthApiResponse: the fields login and registration read.
struct AuthResponse {
  let status: Bool?
  let message: String?
  let description: String?
  let accessToken: String?
  let refreshToken: String?
  /// `data.profile` on LOGIN_SUCCESS and PROFILE_CREATED.
  let profileName: String?
  let profilePhone: String?

  init(_ json: JSONObject) {
    let data = json.object("data") ?? [:]
    let profile = data.object("profile") ?? [:]
    status = json["status"] as? Bool
    message = json.string("message")
    description = json.string("description")
    accessToken = data.string("access")
    refreshToken = data.string("refresh")
    profileName = profile.string("name")
    profilePhone = profile.string("phone_number")
  }
}

/// lib/features/auth/auth_api.dart: unauthenticated login, OTP and
/// registration calls.
struct AuthAPI {
  var baseURL = APIConfig.baseURL

  func requestOTP(phone: String) async throws -> AuthResponse {
    try await post("auth/login/", ["phone_number": phone])
  }

  func verifyOTP(phone: String, otp: String, voipToken: String?) async throws -> AuthResponse {
    var body = ["phone_number": phone, "otp": otp]
    body.merge(Self.deviceFields(voipToken: voipToken)) { $1 }
    return try await post("auth/login/", body)
  }

  func register(phone: String, name: String, voipToken: String?) async throws -> AuthResponse {
    var body = ["phone_number": phone, "name": name]
    body.merge(Self.deviceFields(voipToken: voipToken)) { $1 }
    return try await post("auth/register/", body)
  }

  /// iOS sends "device_type" + "voip_token" (PushKit); no registration_id.
  static func deviceFields(voipToken: String?) -> [String: String] {
    guard let voipToken, !voipToken.isEmpty else { return [:] }
    return ["device_type": "ios", "voip_token": voipToken]
  }

  /// Best effort: the caller signs out whatever this answers.
  func logout(access: String, refresh: String?) async {
    var request = URLRequest(url: URL(string: "auth/logout/", relativeTo: baseURL)!)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: refresh.map { ["refresh": $0] } ?? [:])
    _ = try? await URLSession.shared.data(for: request)
  }

  private func post(_ endpoint: String, _ body: [String: String]) async throws -> AuthResponse {
    var request = URLRequest(url: URL(string: endpoint, relativeTo: baseURL)!)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch let error as URLError {
      throw error.code == .timedOut ? APIError.timeout : APIError.offline
    }
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject else {
      throw APIError(message: "The sign-in service returned an invalid response.")
    }
    let parsed = AuthResponse(json)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    #if DEBUG
      authLog.notice(
        "\(endpoint, privacy: .public) \(code) \(parsed.message ?? "-", privacy: .public): \(parsed.description ?? "-", privacy: .public)"
      )
    #endif
    guard (200..<300).contains(code) else {
      throw APIError(message: parsed.description ?? json.string("detail") ?? "Sign-in failed. Please try again.")
    }
    return parsed
  }
}
