import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class OcrAccountLinkService {
  OcrAccountLinkService({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email']);

  final GoogleSignIn _googleSignIn;

  Future<User> ensureLinkedAccount() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError('No Firebase user is available.');
    }

    if (!currentUser.isAnonymous) {
      return currentUser;
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
      return result.user ?? FirebaseAuth.instance.currentUser!;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        final signInResult = await FirebaseAuth.instance.signInWithCredential(
          credential,
        );
        return signInResult.user ?? FirebaseAuth.instance.currentUser!;
      }
      rethrow;
    }
  }
}
