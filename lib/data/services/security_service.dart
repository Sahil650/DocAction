import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> canAuthenticate() async {
    final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
    final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
    return canAuthenticate;
  }

  Future<bool> authenticate() async {
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Please authenticate to open the Document Scanner',
        biometricOnly: false, // Fallback to PIN/Pattern/Password
      );
      return didAuthenticate;
    } on PlatformException catch (e) {
      print("Auth Platform Error: $e");
      return false;
    } catch (e) {
      print("Auth General Error: $e");
      return false;
    }
  }
}
