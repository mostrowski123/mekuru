import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

/// Lazily initializes Firebase and creates the OCR auth user only when needed.
class FirebaseRuntime {
  FirebaseRuntime._();

  static final FirebaseRuntime instance = FirebaseRuntime._();

  bool get hasFirebaseApp => Firebase.apps.isNotEmpty;

  Future<void> ensureFirebaseApp() async {
    if (hasFirebaseApp) {
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
}
