import Foundation

/// The API answers loosely typed JSON; screens read it the way the Flutter
/// code read `Map<String, dynamic>`.
typealias JSONObject = [String: Any]

/// A JSON true/false. (`is Bool` is also true for any NSNumber 0 or 1, so
/// booleans are told apart by their CoreFoundation type.)
private func isJSONBool(_ value: NSNumber) -> Bool { CFGetTypeID(value) == CFBooleanGetTypeID() }

extension Dictionary where Key == String, Value == Any {
  /// A trimmed, non-empty string (numbers are formatted), else nil.
  func string(_ key: String) -> String? {
    switch self[key] {
    case let value as String:
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    case let value as NSNumber where !isJSONBool(value):
      return value.stringValue
    default:
      return nil
    }
  }

  /// The first of `keys` with a displayable string.
  func string(_ keys: [String]) -> String? {
    for key in keys { if let value = string(key) { return value } }
    return nil
  }

  func int(_ key: String) -> Int? {
    switch self[key] {
    case let value as NSNumber where !isJSONBool(value): return value.intValue
    case let value as String: return Int(value)
    default: return nil
    }
  }

  func double(_ key: String) -> Double? {
    switch self[key] {
    case let value as NSNumber where !isJSONBool(value): return value.doubleValue
    case let value as String: return Double(value)
    default: return nil
    }
  }

  func bool(_ key: String) -> Bool? {
    switch self[key] {
    case let value as Bool: return value
    case let value as NSNumber: return value.boolValue
    case let value as String: return ["true", "1", "yes"].contains(value.lowercased())
    default: return nil
    }
  }

  func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }

  func objects(_ key: String) -> [JSONObject] { (self[key] as? [Any])?.compactMap { $0 as? JSONObject } ?? [] }

  func strings(_ key: String) -> [String] {
    (self[key] as? [Any])?.compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue } ?? []
  }
}
