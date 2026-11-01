import Foundation
import Security

/// lib/features/auth/session_store.dart: the login tokens and the side menu's
/// name and number, in the keychain.
final class SessionStore: @unchecked Sendable {
  static let shared = SessionStore()

  private enum Key: String, CaseIterable {
    case access = "college_guide_access_token"
    case refresh = "college_guide_refresh_token"
    case name = "college_guide_profile_name"
    case phone = "college_guide_profile_phone"
  }

  private let service = "com.minibrain.collegebook.session"
  private let lock = NSLock()
  /// Counts clears, so a request or refresh begun before a logout can't touch
  /// the session that follows it.
  private var clears = 0

  var generation: Int {
    lock.lock()
    defer { lock.unlock() }
    return clears
  }

  var accessToken: String? { read(.access) }
  var refreshToken: String? { read(.refresh) }
  var hasSession: Bool { !(accessToken ?? "").isEmpty }
  var profile: (name: String?, phone: String?) { (read(.name), read(.phone)) }

  func saveTokens(access: String, refresh: String?) {
    write(.access, access)
    write(.refresh, refresh)
  }

  /// A refresh's tokens, unless the session was cleared since `generation`.
  func saveRefreshedTokens(access: String, refresh: String?, generation: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard clears == generation else { return false }
    store(.access, access)
    store(.refresh, refresh)
    return true
  }

  func saveProfile(name: String?, phone: String?) {
    if let name { write(.name, name) }
    if let phone { write(.phone, phone) }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    clearKeys()
  }

  /// Ends the session `generation` belongs to; false if it has already ended.
  func clear(ifGeneration generation: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard clears == generation else { return false }
    clearKeys()
    return true
  }

  private func clearKeys() {
    clears += 1
    for key in Key.allCases { store(key, nil) }
  }

  // MARK: Keychain

  private func query(_ key: Key) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
    ]
  }

  private func read(_ key: Key) -> String? {
    lock.lock()
    defer { lock.unlock() }
    var q = query(key)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func write(_ key: Key, _ value: String?) {
    lock.lock()
    defer { lock.unlock() }
    store(key, value)
  }

  /// The caller holds `lock`.
  private func store(_ key: Key, _ value: String?) {
    let q = query(key)
    SecItemDelete(q as CFDictionary)
    guard let value, let data = value.data(using: .utf8) else { return }
    var add = q
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(add as CFDictionary, nil)
  }
}
