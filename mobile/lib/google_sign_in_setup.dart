import 'package:google_sign_in/google_sign_in.dart';

/// google_sign_in requires its singleton to be initialized exactly once.
class GoogleSignInSetup {
  GoogleSignInSetup._();

  static Future<void>? _initialization;

  static Future<void> initialize(String serverClientId) {
    return _initialization ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
  }
}
