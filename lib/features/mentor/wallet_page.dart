import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/native_bridge.dart';
import '../home/college_guide_api.dart';

const _iconColor = Color(0xFF004D40);

/// The key the native PaymentHelper opens Razorpay checkout with.
const razorpayKey = 'rzp_live_FVZ2nRTnm68LdC';

/// Razorpay checkout as the native PaymentHelper.startPayment opens it.
Map<String, Object?> razorpayOptions({
  required String name,
  required String description,
  required String amount,
  required String email,
  required String contact,
  required String orderId,
}) => {
  'key': razorpayKey,
  'name': name,
  'description': description,
  'image': 'https://www.razorpay.com',
  'theme': {'color': '#2979ff'},
  'order_id': orderId,
  'currency': 'INR',
  'amount': amount,
  'prefill': {'email': email, 'contact': contact},
  'retry': {'enabled': true, 'max_count': 4},
};

/// The native onPaymentError wording for a Razorpay failure code.
String razorpayErrorMessage(PaymentFailureResponse response) {
  final code = response.code;
  final description = response.message ?? '';
  switch (code) {
    case Razorpay.NETWORK_ERROR:
      return 'Network error! Please check your internet connection and try again.';
    case Razorpay.INVALID_OPTIONS:
      return 'Payment failed due to invalid options. Please try again with correct details.';
    case Razorpay.PAYMENT_CANCELLED:
      return 'Payment canceled by the user.';
    case Razorpay.TLS_ERROR:
      return 'Your device does not support the required security protocols for this transaction. Please update your device or try using a different one.';
    default:
      return 'Payment failed. Error code: $code. $description';
  }
}

/// UserWalletRelatedActivity (activity_user_wallet_related.xml): the balance,
/// a grid of top-up amounts and a custom amount, paid through Razorpay.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const _amounts = [
    50,
    100,
    200,
    300,
    400,
    500,
    600,
    700,
    800,
    900,
    1000,
  ];

  final _customController = TextEditingController();
  Razorpay? _razorpay;
  String? _balance;
  int _amount = 0;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _customController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      // walletBalance() answers the response's data object.
      final data = await widget.api.walletBalance();
      final balance = data['balance'];
      if (!mounted || balance == null) return;
      setState(() => _balance = '$balance');
    } on CollegeGuideApiException {
      // The native screen leaves the amount blank.
    }
  }

  void _addCustom() {
    final text = _customController.text.trim();
    if (text.isEmpty) {
      showToast(context, 'Please enter an amount');
      return;
    }
    final value = int.tryParse(text);
    if (value == null) {
      showToast(context, 'Please enter a valid amount');
      return;
    }
    if (value < 50) {
      showToast(context, 'Minimum amount is ₹50');
      return;
    }
    _startPayment(value);
  }

  Future<void> _startPayment(int amount) async {
    _amount = amount;
    final Map<String, dynamic> json;
    try {
      json = await widget.api.send(
        'POST',
        'college/payment/',
        body: {'amount': amount, 'name': 'MiniBrain'},
      );
    } on CollegeGuideApiException catch (e) {
      if (!mounted) return;
      final message = e.payload?['message'];
      showToast(
        context,
        e.payload == null
            ? 'Something went wrong. Please try again.'
            : (message is String && message.isNotEmpty
                  ? message
                  : 'Payment initiation failed'),
      );
      return;
    }
    if (!mounted) return;
    final data = json['data'];
    final payment = data is Map ? data['payment'] : null;
    if (data is! Map || payment is! Map) return;

    final razorpay = _razorpay ??= Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    razorpay.open(
      razorpayOptions(
        name: '${data['name'] ?? 'MiniBrain User'}',
        description: 'WalletPayment',
        amount: '${payment['amount']}',
        email: '${data['email'] ?? ''}',
        contact: '${data['phone_number'] ?? ''}',
        orderId: '${payment['id']}',
      ),
    );
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final orderId = response.orderId ?? 'N/A';
    try {
      await widget.api.send(
        'POST',
        'college/payment/success/',
        body: {
          'razorpay_payment_id': response.paymentId ?? 'N/A',
          'razorpay_order_id': orderId,
          'razorpay_signature': response.signature ?? 'N/A',
        },
      );
      await widget.api.send(
        'POST',
        'college/wallet/add-money/',
        body: {'amount': _amount, 'payment_id': orderId},
      );
    } on CollegeGuideApiException {
      // The native screen stays put when either call gets no answer.
      return;
    }
    if (!mounted) return;
    // Back to CollegeHomePageActivity.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    showToast(context, razorpayErrorMessage(response));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _iconColor,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Container(
              color: _iconColor,
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: const _WalletHeader(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        'Available Balance',
                        style: TextStyle(
                          color: Color(0xFF474747),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Text(
                        _balance == null ? '' : '₹ $_balance',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      // GridLayoutManager(3): rows of three equal cells.
                      child: Column(
                        children: [
                          for (var i = 0; i < _amounts.length; i += 3)
                            Row(
                              children: [
                                for (var j = i; j < i + 3; j++)
                                  Expanded(
                                    child: j < _amounts.length
                                        ? _AmountCard(
                                            amount: _amounts[j],
                                            onTap: () =>
                                                _startPayment(_amounts[j]),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Text(
                        'Or enter custom amount',
                        style: TextStyle(
                          color: Color(0xFF474747),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFC5C5C5)),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            '₹',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const Key('walletCustomAmount'),
                              controller: _customController,
                              keyboardType: TextInputType.number,
                              // inputType="number": digits only.
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              maxLines: 1,
                              cursorColor: _iconColor,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Minimum ₹50',
                                hintStyle: TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.all(10),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _addCustom,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _iconColor,
                                borderRadius: BorderRadius.circular(360),
                              ),
                              child: const Text(
                                'Add',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 12),
          Semantics(
            label: 'Back',
            button: true,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: SvgPicture.asset(
                'assets/icons/ic_baseline_arrow_back_24.svg',
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          const Text(
            'Add money to wallet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              // TextView font padding.
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// row_add_wallet.xml: a 12dp outlined card with the amount over a green
/// "100% extra" strip.
class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amount, required this.onTap});

  final int amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: const Color(0xFFFDF7FD),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFEAEAEA)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Text(
                  '₹ $amount',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: const Color(0xFFE9F3EC),
                alignment: Alignment.center,
                child: const Text(
                  '100% extra',
                  style: TextStyle(
                    color: Color(0xFF28A745),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
