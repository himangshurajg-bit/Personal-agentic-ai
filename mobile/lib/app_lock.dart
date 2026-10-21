import 'package:local_auth/local_auth.dart';

/// Boundary around the operating-system authentication prompt.
/// Tests can supply a deterministic implementation; no credential is read or stored here.
abstract interface class DeviceAuthenticator {
  Future<bool> authenticate();
}

class LocalAuthDeviceAuthenticator implements DeviceAuthenticator {
  final LocalAuthentication _localAuth;

  LocalAuthDeviceAuthenticator({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  @override
  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Personal assistant',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      // Cancellation, unavailable hardware, and platform errors all deny access.
      return false;
    }
  }
}
