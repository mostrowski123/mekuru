import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Lazily initializes Firebase and creates the OCR auth user only when needed.
class FirebaseRuntime {
  FirebaseRuntime._();

  static final FirebaseRuntime instance = FirebaseRuntime._();

  bool _appCheckActivated = false;

  bool get hasFirebaseApp => Firebase.apps.isNotEmpty;

  Future<void> ensureFirebaseApp() async {
    if (!hasFirebaseApp) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    await _ensureAppCheck();
  }

  Future<User> ensureOcrUser() async {
    await ensureFirebaseApp();

    final auth = FirebaseAuth.instance;
    final existingUser = auth.currentUser;
    if (existingUser != null) {
      return existingUser;
    }

    final credential = await auth.signInAnonymously();
    return credential.user ??
        auth.currentUser ??
        (throw StateError('Failed to create an OCR user.'));
  }

  Future<String?> getAppCheckToken({bool forceRefresh = false}) async {
    await ensureFirebaseApp();
    return FirebaseAppCheck.instance.getToken(forceRefresh);
  }

  Future<void> _ensureAppCheck() async {
    if (_appCheckActivated) {
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
    _appCheckActivated = true;
  }
}
