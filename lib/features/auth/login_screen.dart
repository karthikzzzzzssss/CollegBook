import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/native_bridge.dart';
import '../../theme/app_theme.dart';
import '../home/college_guide_api.dart';
import '../home/home_shell.dart';
import 'auth_api.dart';
import 'register_screen.dart';
import 'session_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.authRepository,
    this.apiRepository,
    this.sessionStore,
  });

  final AuthRepository? authRepository;
  final CollegeGuideApiRepository? apiRepository;
  final SessionStore? sessionStore;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  late final AuthRepository _authRepository;
  late final SessionStore _sessionStore;
  late final bool _ownsAuthRepository;
  Timer? _resendTimer;
  bool _showOtpStep = false;
  bool _isBusy = false;
  int _resendSecondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _ownsAuthRepository = widget.authRepository == null;
    _authRepository = widget.authRepository ?? AuthRepository();
    _sessionStore = widget.sessionStore ?? SecureSessionStore();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    if (_ownsAuthRepository) _authRepository.close();
    super.dispose();
  }

  Future<void> _continueToOtp() async {
    if (_isBusy) return;
    if (_phoneController.text.trim().length != 10) {
      _showNotice('Please enter a valid number');
      return;
    }
    setState(() {
      _isBusy = true;
    });

    try {
      final response = await _authRepository.requestOtp(
        _phoneController.text.trim(),
      );
      if (!mounted) return;
      if (response.status == false) {
        throw AuthApiException(
          response.description ?? 'Could not send an OTP. Please try again.',
        );
      }

      setState(() {
        _showOtpStep = true;
        _otpController.clear();
      });
      _startResendTimer();
      _showNotice(
        response.description ??
            'If this number is registered, an OTP has been sent by SMS.',
        isError: false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocusNode.requestFocus();
      });
    } on AuthApiException catch (error) {
      if (mounted) _showNotice(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_isBusy) return;
    final otp = _otpController.text.trim();
    if (!RegExp(r'^[0-9]{4}$').hasMatch(otp)) {
      _showNotice('Please enter OTP', isError: true);
      return;
    }

    setState(() {
      _isBusy = true;
    });

    try {
      // Like the native app: ask for notifications first, then verify either way.
      await requestNotificationPermission();
      final token = await fcmToken();
      final voip = await voipToken();
      if (!mounted) return;
      final response = await _authRepository.verifyOtp(
        phoneNumber: _phoneController.text.trim(),
        otp: otp,
        fcmToken: token,
        voipToken: voip,
      );
      if (!mounted) return;
      if (response.status == false) {
        _otpController.clear();
        _showNotice(
          response.description ?? 'Please enter correct OTP',
          isError: true,
        );
        return;
      }

      if (response.message == 'LOGIN_SUCCESS') {
        final accessToken = response.accessToken;
        if (accessToken == null) {
          _showNotice(
            'The server did not return an access token. Please try again.',
            isError: true,
          );
          return;
        }

        await _sessionStore.saveTokens(
          accessToken: accessToken,
          refreshToken: response.refreshToken,
        );
        await _sessionStore.saveProfile(
          name: response.profileName,
          phone: response.profilePhone ?? _phoneController.text.trim(),
        );
        if (!mounted) return;
        _resendTimer?.cancel();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => HomeShell(
              apiRepository: widget.apiRepository,
              sessionStore: _sessionStore,
            ),
          ),
          (_) => false,
        );
        return;
      }

      if (response.message == 'NEW_USER') {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RegisterScreen(
              phoneNumber: _phoneController.text.trim(),
              authRepository: _authRepository,
              apiRepository: widget.apiRepository,
              sessionStore: _sessionStore,
            ),
          ),
        );
        return;
      }

      // Wrong / expired OTP: let them type it again.
      _otpController.clear();
      _showNotice(
        response.description ?? 'Please enter correct OTP',
        isError: true,
      );
    } on AuthApiException catch (error) {
      if (mounted) {
        _otpController.clear();
        _showNotice(error.message, isError: true);
      }
    } on PlatformException {
      if (mounted) {
        _showNotice(
          'Sign-in succeeded, but the secure session could not be saved.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_isBusy || _resendSecondsRemaining > 0) return;
    setState(() {
      _isBusy = true;
    });

    try {
      final response = await _authRepository.requestOtp(
        _phoneController.text.trim(),
      );
      if (!mounted) return;
      if (response.status == false) {
        throw AuthApiException(
          response.description ?? 'Could not resend the OTP. Please try again.',
        );
      }
      _otpController.clear();
      _showNotice(
        response.description ?? 'A new OTP has been sent by SMS.',
        isError: false,
      );
      _startResendTimer();
    } on AuthApiException catch (error) {
      if (mounted) _showNotice(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    setState(() {
      _showOtpStep = false;
      _isBusy = false;
      _resendSecondsRemaining = 0;
      _otpController.clear();
    });
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsRemaining = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _resendSecondsRemaining = 0);
      } else {
        setState(() => _resendSecondsRemaining--);
      }
    });
  }

  void _showNotice(String message, {bool isError = true}) {
    if (!mounted) return;
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.primary,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // Back on the OTP step returns to the number step instead of leaving.
      child: PopScope(
        canPop: !_showOtpStep,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _showOtpStep) _changeNumber();
        },
        child: Scaffold(
          backgroundColor: AppColors.primary,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(child: _BrandHeader()),
                        const SizedBox(height: 12),
                        Flexible(
                          flex: 0,
                          fit: FlexFit.loose,
                          child: SingleChildScrollView(
                            child: _LoginCard(
                              formKey: _formKey,
                              phoneController: _phoneController,
                              otpController: _otpController,
                              otpFocusNode: _otpFocusNode,
                              showOtpStep: _showOtpStep,
                              isBusy: _isBusy,
                              resendSecondsRemaining: _resendSecondsRemaining,
                              onContinue: _continueToOtp,
                              onVerify: _verifyOtp,
                              onChangeNumber: _changeNumber,
                              onResend: _resendOtp,
                              onInvalidFirstDigit: () => _showNotice(
                                'Number must start with 6, 7, 8, or 9',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors the native filter: only 6, 7, 8 or 9 may start the number.
class _FirstDigitFormatter extends TextInputFormatter {
  const _FirstDigitFormatter(this.onRejected);

  final VoidCallback onRejected;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isNotEmpty && !'6789'.contains(newValue.text[0])) {
      onRejected();
      return oldValue;
    }
    return newValue;
  }
}

/// The PinView's cursor: a 2dp icon_color bar in the next empty box.
class _PinCursor extends StatelessWidget {
  const _PinCursor();

  @override
  Widget build(BuildContext context) {
    return Container(width: 2, height: 24, color: AppColors.primary);
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/collegebook_splash.png',
      key: const Key('collegeBookLoginArtwork'),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.school_rounded, color: Colors.white, size: 38),
          const SizedBox(height: 10),
          const Text(
            'CollegeBook',
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Your guide to the next step',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.phoneController,
    required this.otpController,
    required this.otpFocusNode,
    required this.showOtpStep,
    required this.isBusy,
    required this.resendSecondsRemaining,
    required this.onContinue,
    required this.onVerify,
    required this.onChangeNumber,
    required this.onResend,
    required this.onInvalidFirstDigit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final FocusNode otpFocusNode;
  final bool showOtpStep;
  final bool isBusy;
  final int resendSecondsRemaining;
  final VoidCallback onContinue;
  final VoidCallback onVerify;
  final VoidCallback onChangeNumber;
  final VoidCallback onResend;
  final VoidCallback onInvalidFirstDigit;

  @override
  Widget build(BuildContext context) {
    final formattedPhone = phoneController.text.length == 10
        ? '${phoneController.text.substring(0, 5)} ${phoneController.text.substring(5)}'
        : phoneController.text;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              showOtpStep ? 'Verify your number' : "Let's get started",
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            if (showOtpStep)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Enter the 4-digit code sent to\n+91 $formattedPhone',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('changeNumberButton'),
                    onPressed: isBusy ? null : onChangeNumber,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Change',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Login or sign up with your mobile number',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            const SizedBox(height: 24),
            if (!showOtpStep)
              // Native ll_mobile: 54dp white box, 1dp icon_color outline,
              // "+91 | number".
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Row(
                  children: [
                    const Text(
                      '+91',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: AppColors.primary,
                    ),
                    Expanded(
                      child: TextField(
                        key: const Key('phoneField'),
                        controller: phoneController,
                        enabled: !isBusy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [
                          AutofillHints.telephoneNumberNational,
                        ],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                          _FirstDigitFormatter(onInvalidFirstDigit),
                        ],
                        cursorColor: AppColors.primary,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.64,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter mobile number',
                          hintStyle: TextStyle(
                            color: Color(0x80004D40),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.64,
                          ),
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                        onSubmitted: (_) => onContinue(),
                      ),
                    ),
                  ],
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 4 * 56 + 3 * 14,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      TextFormField(
                        key: const Key('otpField'),
                        controller: otpController,
                        focusNode: otpFocusNode,
                        enabled: !isBusy,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        showCursor: false,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.transparent,
                          fontSize: 20,
                          height: 1,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                        ),
                        onFieldSubmitted: (_) => onVerify(),
                      ),
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          otpController,
                          otpFocusNode,
                        ]),
                        builder: (context, child) {
                          final digits = otpController.text;
                          final hasFocus = otpFocusNode.hasFocus;
                          return IgnorePointer(
                            child: Row(
                              children: List.generate(4, (index) {
                                final showCursor =
                                    hasFocus &&
                                    index == digits.length.clamp(0, 3) &&
                                    digits.length < 4;
                                return Padding(
                                  padding: EdgeInsets.only(
                                    left: index == 0 ? 0 : 14,
                                  ),
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: showCursor
                                        ? const _PinCursor()
                                        : Text(
                                            index < digits.length
                                                ? digits[index]
                                                : '',
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                );
                              }),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (showOtpStep) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Didn't receive the OTP?",
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (resendSecondsRemaining > 0) ...[
                        const Text(
                          'Resend in',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '0:${resendSecondsRemaining.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Color(0xFF1C1E21),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else
                        TextButton(
                          key: const Key('resendOtpButton'),
                          onPressed: isBusy ? null : onResend,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Resend',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ] else
              const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: Key(showOtpStep ? 'verifyButton' : 'continueButton'),
                onPressed: isBusy
                    ? null
                    : (showOtpStep ? onVerify : onContinue),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: isBusy
                    ? const SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        showOtpStep ? 'Verify' : 'Continue',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              showOtpStep
                  ? 'By continuing you agree to our Terms & Privacy Policy'
                  : "We'll send a 4-digit OTP to verify your number",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.primary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
