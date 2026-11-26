import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_profile.dart';

/// Failures a user could act on, kept separate from cancelled sign-ins.
class AuthException implements Exception {
  const AuthException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Google OAuth configuration.
///
/// Native apps must use an *iOS* OAuth client, not the website's web client, and
/// the matching reversed-client-id URL scheme has to be registered in
/// `ios/Runner/Info.plist` (see `flutter/README.md`). The id lives here so the
/// app can explain what is missing instead of failing behind a browser that can
/// never call back.
class GoogleAuthConfig {
  const GoogleAuthConfig._();

  /// e.g. `248585696121-xxxxxxxx.apps.googleusercontent.com`
  static const String iosClientId =
      '248585696121-na51ejn86vfi93ks82057l95dohsocsn.apps.googleusercontent.com';

  static const String _clientIdSuffix = '.apps.googleusercontent.com';

  static bool get isConfigured =>
      iosClientId.trim().isNotEmpty && iosClientId.contains(_clientIdSuffix);

  /// Returns `null` when sign-in can run, otherwise what has to be fixed.
  static String? get configurationProblem {
    final value = iosClientId.trim();
    if (value.isEmpty) {
      return 'No iOS OAuth client ID set. Add one to '
          'GoogleAuthConfig.iosClientId in lib/services/google_auth_service.dart.';
    }
    if (!value.contains(_clientIdSuffix)) {
      return '`$value` does not look like a Google iOS client ID.';
    }
    return null;
  }

  /// Google's iOS redirect scheme is the reversed client ID.
  static String? get reversedClientId {
    final value = iosClientId.trim();
    if (!value.contains(_clientIdSuffix)) {
      return null;
    }
    final prefix = value.replaceAll(_clientIdSuffix, '');
    return 'com.googleusercontent.apps.$prefix';
  }
}

/// Native "Sign in with Google", backed by the platform SDK.
class GoogleAuthService {
  GoogleSignIn? _signIn;
  bool _initialized = false;

  Future<GoogleSignIn> _ensureInitialized() async {
    final existing = _signIn;
    if (existing != null && _initialized) {
      return existing;
    }
    if (GoogleAuthConfig.configurationProblem != null) {
      throw AuthException(GoogleAuthConfig.configurationProblem!);
    }

    final instance = GoogleSignIn.instance;
    await instance.initialize(clientId: GoogleAuthConfig.iosClientId.trim());
    _signIn = instance;
    _initialized = true;
    return instance;
  }

  /// Runs the interactive flow and returns the signed-in account.
  Future<UserProfile> signIn() async {
    final problem = GoogleAuthConfig.configurationProblem;
    if (problem != null) {
      throw AuthException(problem);
    }

    final googleSignIn = await _ensureInitialized();
    if (!googleSignIn.supportsAuthenticate()) {
      throw const AuthException(
        'Google Sign-In needs the platform SDK, which is unavailable here. '
        'Run the app on iOS or Android.',
      );
    }

    try {
      final account = await googleSignIn.authenticate();
      return await _profileFrom(account);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Sign-in cancelled', cancelled: true);
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw AuthException(
          'Google rejected this build\'s OAuth client. Check that the client ID '
          'and the reversed-client-id URL scheme match an iOS client for this '
          'bundle id. (${error.description ?? error.code.name})',
        );
      }
      throw AuthException(
        'Google sign-in failed: ${error.description ?? error.code.name}',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _signIn?.signOut();
    } on GoogleSignInException {
      // Signing out locally is what matters; the SDK's state is secondary.
    }
  }

  Future<UserProfile> _profileFrom(GoogleSignInAccount account) async {
    // The ID token is the only thing the workers can verify; without it admin
    // and community writes are rejected. Missing it is not fatal for browsing.
    String idToken = '';
    try {
      idToken = account.authentication.idToken ?? '';
    } on GoogleSignInException {
      idToken = '';
    }

    final name = account.displayName;
    return UserProfile(
      name: name != null && name.trim().isNotEmpty ? name : account.email,
      email: account.email,
      picture: account.photoUrl ?? '',
      idToken: idToken,
    );
  }
}
