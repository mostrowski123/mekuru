import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/services/firebase_runtime.dart';

class OcrLinkedAccountResult {
  final User user;
  final bool linkedThisCall;

  const OcrLinkedAccountResult({
    required this.user,
    required this.linkedThisCall,
  });
}

class OcrAccountLinkService {
  static bool _googleSignInInitialized = false;

  Future<OcrLinkedAccountResult> ensureLinkedAccount() async {
    await FirebaseRuntime.instance.ensureFirebaseApp();
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;

    if (currentUser != null && !currentUser.isAnonymous) {
      return OcrLinkedAccountResult(user: currentUser, linkedThisCall: false);
    }

    final credential = await _signInWithGoogle();
    if (currentUser == null) {
      return _signInWithCredential(auth, credential);
    }

    return _linkAnonymousUser(auth, currentUser, credential);
  }

  Future<AuthCredential> _signInWithGoogle() async {
    if (!_googleSignInInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleSignInInitialized = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw StateError('Google sign-in was cancelled.');
      }
      rethrow;
    }

    return GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
  }

  Future<OcrLinkedAccountResult> _linkAnonymousUser(
    FirebaseAuth auth,
    User currentUser,
    AuthCredential credential,
  ) async {
    try {
      final result = await currentUser.linkWithCredential(credential);
      return OcrLinkedAccountResult(
        user: result.user ?? auth.currentUser!,
        linkedThisCall: true,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        return _signInWithCredential(auth, credential);
      }
      throw _describeAuthError(e);
    }
  }

  Future<OcrLinkedAccountResult> _signInWithCredential(
    FirebaseAuth auth,
    AuthCredential credential,
  ) async {
    try {
      final signInResult = await auth.signInWithCredential(credential);
      return OcrLinkedAccountResult(
        user: signInResult.user ?? auth.currentUser!,
        linkedThisCall: true,
      );
    } on FirebaseAuthException catch (e) {
      throw _describeAuthError(e);
    }
  }

  Object _describeAuthError(FirebaseAuthException error) {
    if (error.code == 'too-many-requests') {
      return StateError(
        'Too many recent sign-in attempts. Wait a few minutes, then try again.',
      );
    }

    return error;
  }
}
