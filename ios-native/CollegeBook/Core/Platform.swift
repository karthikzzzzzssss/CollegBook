import UIKit

/// native_bridge.dart's platform helpers.
enum Platform {
  /// callNumber(): the dialer with the number filled in.
  static func call(_ number: String) {
    let digits = number.filter { $0.isNumber || $0 == "+" }
    guard let url = URL(string: "tel://\(digits)") else { return }
    UIApplication.shared.open(url)
  }

  /// openUrl(): Safari, or the app that owns a universal link.
  static func open(_ string: String) {
    guard let url = URL(string: string) else { return }
    UIApplication.shared.open(url)
  }

  /// shareText(): the system share sheet over the top-most screen.
  static func share(_ text: String, subject: String? = nil) {
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    if let subject { sheet.setValue(subject, forKey: "subject") }
    topViewController()?.present(sheet, animated: true)
  }

  static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
