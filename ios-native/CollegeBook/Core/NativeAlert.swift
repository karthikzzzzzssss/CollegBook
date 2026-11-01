import UIKit

/// native_dialog.dart showNativeAlert(): a system alert over whatever is on
/// screen; true for the positive button.
enum NativeAlert {
  @MainActor
  static func show(
    title: String, message: String, negative: String? = nil, positive: String, destructive: Bool = false
  ) async -> Bool {
    await withCheckedContinuation { continuation in
      let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
      if let negative {
        alert.addAction(UIAlertAction(title: negative, style: .cancel) { _ in continuation.resume(returning: false) })
      }
      alert.addAction(
        UIAlertAction(title: positive, style: destructive ? .destructive : .default) { _ in
          continuation.resume(returning: true)
        })
      // UIKit drops a present from a screen off-window or mid-transition, and
      // then no button would ever answer.
      guard let top = Platform.topViewController(), top.viewIfLoaded?.window != nil, !top.isBeingPresented,
        !top.isBeingDismissed
      else { return continuation.resume(returning: false) }
      top.present(alert, animated: true)
    }
  }

  /// A blocking spinner (the fragment's progress bar), dismissed by the
  /// returned closure.
  @MainActor
  static func progress() -> () -> Void {
    let host = UIViewController()
    host.view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.color = .white
    spinner.translatesAutoresizingMaskIntoConstraints = false
    host.view.addSubview(spinner)
    NSLayoutConstraint.activate([
      spinner.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
    ])
    spinner.startAnimating()
    host.modalPresentationStyle = .overFullScreen
    host.modalTransitionStyle = .crossDissolve
    Platform.topViewController()?.present(host, animated: false)
    return { host.dismiss(animated: false) }
  }
}
