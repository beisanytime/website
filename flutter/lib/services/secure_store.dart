import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user_profile.dart';

/// Storage for credentials.
///
/// The Google session and the server-side upload password must not sit in
/// `SharedPreferences`, an unprotected file inside the app container — the same
/// reasoning that put them in the iOS Keychain.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'googleUser';
  static const String _uploadPasswordKey = 'uploadPassword';

  Future<void> saveUser(UserProfile user) => _storage.write(
        key: _sessionKey,
        value: jsonEncode(user.toJson()),
      );

  Future<UserProfile?> loadUser() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UserProfile.fromJson(decoded);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> clearUser() => _storage.delete(key: _sessionKey);

  Future<void> saveUploadPassword(String password) =>
      _storage.write(key: _uploadPasswordKey, value: password);

  Future<String?> loadUploadPassword() =>
      _storage.read(key: _uploadPasswordKey);

  Future<void> clearUploadPassword() =>
      _storage.delete(key: _uploadPasswordKey);
}
