import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

const _forceDebugAppCheckProvider = bool.fromEnvironment(
  'FORCE_DEBUG_APP_CHECK_PROVIDER',
);

/// Lazily initializes Firebase and creates the OCR auth user only when needed.
class FirebaseRuntime {
  FirebaseRuntime._();

  static final FirebaseRuntime instance = FirebaseRuntime._();

  bool _appCheckActivated = false;
  DateTime? _appCheckRetryAfter;

  bool get hasFirebaseApp => Firebase.apps.isNotEmpty;

  bool get usesDebugAppCheckProvider =>
      kDebugMode || _forceDebugAppCheckProvider;

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

    final retryAfter = _appCheckRetryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      throw FirebaseException(
        plugin: 'firebase_app_check',
        code: 'too-many-requests',
        message:
            'Firebase App Check is temporarily rate limited. '
            'Wait a few minutes and try again.',
      );
    }

    try {
      final token = await FirebaseAppCheck.instance.getToken(forceRefresh);
      _appCheckRetryAfter = null;
      return token;
    } on FirebaseException catch (error) {
      final message = error.message?.toLowerCase() ?? '';
      if (error.code == 'too-many-requests' ||
          message.contains('too many attempts')) {
        // Play Integrity can briefly throttle repeated local test attempts.
        _appCheckRetryAfter = DateTime.now().add(const Duration(minutes: 5));
      }
      rethrow;
    }
  }

  Future<void> _ensureAppCheck() async {
    if (_appCheckActivated) {
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerAndroid: usesDebugAppCheckProvider
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
    _appCheckActivated = true;
  }
}
