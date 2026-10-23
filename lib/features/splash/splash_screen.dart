import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.duration,
    required this.nextScreen,
  });

  final Duration duration;
  final Widget nextScreen;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => widget.nextScreen),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the home banner while the splash shows, so it is drawn on the
    // first frame of Home instead of a grey box.
    precacheImage(
      const AssetImage('assets/images/collegebook_home_banner.png'),
      context,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
        body: SizedBox.expand(
          child: Image.asset(
            'assets/images/collegebooksplash.png',
            key: const Key('collegeBookSplash'),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
