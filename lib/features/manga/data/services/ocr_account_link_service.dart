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
    final currentUser = await FirebaseRuntime.instance.ensureOcrUser();

    if (!currentUser.isAnonymous) {
      return OcrLinkedAccountResult(user: currentUser, linkedThisCall: false);
    }

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

    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );

    try {
      final result = await currentUser.linkWithCredential(credential);
      return OcrLinkedAccountResult(
        user: result.user ?? FirebaseAuth.instance.currentUser!,
        linkedThisCall: true,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final signInResult = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        return OcrLinkedAccountResult(
          user:
              signInResult.user ??
              FirebaseAuth.instance.currentUser ??
              currentUser,
          linkedThisCall: true,
        );
      }
      rethrow;
    }
  }
}
