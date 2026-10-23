import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  runApp(const CollegeGuideApp());
}

/// The native app's Firebase project (android/app/google-services.json):
/// Crashlytics for crashes, Messaging for mentor call pushes. iOS has no
/// GoogleService-Info.plist yet, so it runs without Firebase.
Future<void> _initFirebase() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    await Firebase.initializeApp();
  } on Object catch (e) {
    debugPrint('Firebase init failed: ${e.runtimeType}');
    return;
  }
  final crashlytics = FirebaseCrashlytics.instance;
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crashlytics.recordError(error, stack, fatal: true));
    return true;
  };
}
