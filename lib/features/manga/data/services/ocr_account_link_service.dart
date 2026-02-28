import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class OcrLinkedAccountResult {
  final User user;
  final bool linkedThisCall;

  const OcrLinkedAccountResult({
    required this.user,
    required this.linkedThisCall,
  });
}

class OcrAccountLinkService {
  OcrAccountLinkService({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final GoogleSignIn _googleSignIn;

  Future<OcrLinkedAccountResult> ensureLinkedAccount() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('No Firebase user is available.');
    }

    if (!currentUser.isAnonymous) {
      return OcrLinkedAccountResult(user: currentUser, linkedThisCall: false);
    }

    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('Google sign-in was cancelled.');
    }

    final auth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
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
          user: signInResult.user ?? FirebaseAuth.instance.currentUser!,
          linkedThisCall: true,
        );
      }
      rethrow;
    }
  }
}
