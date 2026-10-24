import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/native_bridge.dart';
import '../../theme/app_theme.dart';
import '../home/college_guide_api.dart';
import '../home/home_shell.dart';
import 'auth_api.dart';
import 'session_store.dart';

/// Native `all_india`: the pale green used for text and outlines on this screen.
const _allIndia = Color(0xFFE0FFC2);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.phoneNumber,
    required this.authRepository,
    required this.sessionStore,
    this.apiRepository,
  });

  final String phoneNumber;
  final AuthRepository authRepository;
  final SessionStore sessionStore;
  final CollegeGuideApiRepository? apiRepository;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_isBusy) return;
    if (_nameController.text.trim().isEmpty) {
      _showNotice('Please enter your name');
      return;
    }
    setState(() => _isBusy = true);

    try {
      // Like the native app: ask for notifications first, then register either way.
      await requestNotificationPermission();
      final token = await fcmToken();
      final voip = await voipToken();
      if (!mounted) return;
      final response = await widget.authRepository.register(
        phoneNumber: widget.phoneNumber,
        name: _nameController.text.trim(),
        fcmToken: token,
        voipToken: voip,
      );
      if (!mounted) return;
      if (response.status != true || response.message != 'PROFILE_CREATED') {
        _showNotice('Registration failed. Please try again.');
        return;
      }

      final accessToken = response.accessToken;
      if (accessToken == null) {
        _showNotice(
          'The server did not return an access token. Please try again.',
        );
        return;
      }

      await widget.sessionStore.saveTokens(
        accessToken: accessToken,
        refreshToken: response.refreshToken,
      );
      // The typed name when the response leaves it out.
      await widget.sessionStore.saveProfile(
        name: response.profileName ?? _nameController.text.trim(),
        phone: response.profilePhone ?? widget.phoneNumber,
      );
      if (!mounted) return;
      final description = response.description;
      if (description != null) _showNotice(description);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => HomeShell(
            apiRepository: widget.apiRepository,
            sessionStore: widget.sessionStore,
          ),
        ),
        (_) => false,
      );
    } on AuthApiException catch (error) {
      if (mounted) _showNotice(error.message);
    } on PlatformException {
      if (mounted) {
        _showNotice(
          'Registration succeeded, but the secure session could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  OutlineInputBorder _nameBorder(double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: _allIndia, width: width),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.primary,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.primary,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                // Title centred across the screen, back arrow 16dp from the
                // start edge and vertically centred on the title.
                Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        color: _allIndia,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      child: GestureDetector(
                        key: const Key('registrationBackButton'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _isBusy
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        child: Semantics(
                          label: 'Back',
                          button: true,
                          child: const Icon(
                            Icons.arrow_back,
                            color: _allIndia,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 100),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Full name *',
                        style: TextStyle(
                          color: _allIndia,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('registrationNameField'),
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        enabled: !_isBusy,
                        maxLines: 1,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        cursorColor: AppColors.primary,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your full name',
                          hintStyle: const TextStyle(
                            color: Color(0x80004D40),
                            fontSize: 16,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: _nameBorder(1.5),
                          enabledBorder: _nameBorder(1.5),
                          disabledBorder: _nameBorder(1.5),
                          focusedBorder: _nameBorder(2),
                        ),
                        onSubmitted: (_) => _register(),
                      ),
                      const SizedBox(height: 42),
                      Center(
                        child: Material(
                          color: _allIndia,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            key: const Key('registrationContinueButton'),
                            borderRadius: BorderRadius.circular(8),
                            onTap: _isBusy ? null : _register,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 42,
                                vertical: 10,
                              ),
                              child: _isBusy
                                  ? const SizedBox(
                                      width: 58,
                                      height: 19,
                                      child: Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'Continue',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
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
      ),
    );
  }
}
