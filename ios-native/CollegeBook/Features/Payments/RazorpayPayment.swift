import Razorpay
import UIKit

/// Razorpay checkout as the native PaymentHelper.startPayment opens it.
@MainActor
final class RazorpayPayment: NSObject, RazorpayPaymentCompletionProtocolWithData {
  /// The key the native PaymentHelper opens Razorpay checkout with.
  static let key = "rzp_live_FVZ2nRTnm68LdC"
  /// Paid, but the server hasn't taken it in.
  static let unconfirmedMessage = "Payment received. We couldn't confirm it yet - please contact support if it doesn't appear soon."

  struct Success {
    let paymentId: String
    let orderId: String
    let signature: String
  }

  private var checkout: RazorpayCheckout?
  private var continuation: CheckedContinuation<Result<Success, PaymentError>, Never>?

  struct PaymentError: Error {
    let message: String
  }

  /// Opens checkout and waits for the outcome.
  func pay(name: String, description: String, amount: String, email: String, contact: String, orderId: String) async
    -> Result<Success, PaymentError>
  {
    // A second continuation would orphan the first and mix up the two payments.
    guard continuation == nil else { return .failure(PaymentError(message: "Payment already in progress")) }
    let options: [String: Any] = [
      "key": Self.key,
      "name": name,
      "description": description,
      "image": "https://www.razorpay.com",
      "theme": ["color": "#2979ff"],
      "order_id": orderId,
      "currency": "INR",
      "amount": amount,
      "prefill": ["email": email, "contact": contact],
      "retry": ["enabled": true, "max_count": 4],
    ]
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      let checkout = RazorpayCheckout.initWithKey(Self.key, andDelegateWithData: self)
      self.checkout = checkout
      if let top = Platform.topViewController() {
        checkout.open(options, displayController: top)
      } else {
        checkout.open(options)
      }
    }
  }

  /// college/payment/success/, tried once more if it fails: the money has
  /// already been taken.
  func confirm(_ success: Success, api: APIClient) async throws {
    let body: JSONObject = [
      "razorpay_payment_id": success.paymentId, "razorpay_order_id": success.orderId,
      "razorpay_signature": success.signature,
    ]
    do {
      try await api.request("POST", "college/payment/success/", body: body)
    } catch {
      try? await Task.sleep(seconds: 1)
      try await api.request("POST", "college/payment/success/", body: body)
    }
  }

  nonisolated func onPaymentSuccess(_ payment_id: String, andData response: [AnyHashable: Any]?) {
    let data = response ?? [:]
    let success = Success(
      paymentId: data["razorpay_payment_id"] as? String ?? payment_id,
      orderId: data["razorpay_order_id"] as? String ?? "N/A",
      signature: data["razorpay_signature"] as? String ?? "N/A")
    Task { @MainActor in self.finish(.success(success)) }
  }

  nonisolated func onPaymentError(_ code: Int32, description str: String, andData response: [AnyHashable: Any]?) {
    let message = Self.errorMessage(code: Int(code), description: str)
    Task { @MainActor in self.finish(.failure(PaymentError(message: message))) }
  }

  private func finish(_ result: Result<Success, PaymentError>) {
    continuation?.resume(returning: result)
    continuation = nil
    checkout = nil
  }

  /// The native onPaymentError wording for a Razorpay failure code.
  nonisolated static func errorMessage(code: Int, description: String) -> String {
    switch code {
    case 0: "Network error! Please check your internet connection and try again."
    case 1: "Payment failed due to invalid options. Please try again with correct details."
    case 2: "Payment canceled by the user."
    case 3:
      "Your device does not support the required security protocols for this transaction. Please update your device or try using a different one."
    default: "Payment failed. Error code: \(code). \(description)"
    }
  }
}
