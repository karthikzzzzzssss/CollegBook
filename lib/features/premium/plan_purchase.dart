import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../home/college_guide_api.dart';
import '../mentor/wallet_page.dart' show razorpayOptions;
import 'plan_card.dart';

/// Buying a plan, as PremiumFragment / CollegePackagesActivity do it:
/// POST college/payment/ for an order, Razorpay checkout, then on success
/// college/payment/success/ and college/membership/ {plan_id, payment_id}.
class PlanPurchase {
  PlanPurchase({required this.api, required this.onPurchased});

  final CollegeGuideApiRepository api;

  /// The membership call's message once a plan is bought.
  final void Function(String message) onPurchased;

  Razorpay? _razorpay;
  String? _planId;

  void dispose() => _razorpay?.clear();

  Future<void> buy(Plan plan) async {
    _planId = plan.id;
    final Map<String, dynamic> json;
    try {
      json = await api.send(
        'POST',
        'college/payment/',
        body: {'amount': plan.price, 'name': 'collegeplan'},
      );
    } on CollegeGuideApiException {
      // The native screens only log a failed order.
      return;
    }
    final data = json['data'];
    final payment = data is Map ? data['payment'] : null;
    if (data is! Map || payment is! Map) return;
    final razorpay = _razorpay ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (_) {
        // Logged only, as natively.
      });
    razorpay.open(
      razorpayOptions(
        name: '${data['name'] ?? ''}',
        description: 'college packages',
        amount: '${payment['amount']}',
        email: '${data['email'] ?? ''}',
        contact: '${data['phone_number'] ?? ''}',
        orderId: '${payment['id']}',
      ),
    );
  }

  Future<void> _onSuccess(PaymentSuccessResponse response) async {
    final orderId = response.orderId ?? 'N/A';
    try {
      await api.send(
        'POST',
        'college/payment/success/',
        body: {
          'razorpay_payment_id': response.paymentId ?? 'N/A',
          'razorpay_order_id': orderId,
          'razorpay_signature': response.signature ?? 'N/A',
        },
      );
      final json = await api.send(
        'POST',
        'college/membership/',
        body: {'plan_id': _planId, 'payment_id': orderId},
      );
      onPurchased('${json['message'] ?? ''}');
    } on CollegeGuideApiException {
      // Logged only, as natively.
    }
  }
}
