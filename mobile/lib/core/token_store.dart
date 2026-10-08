import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the login tokens, role and profile in the device's secure storage.
class TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _key = 'mk_session';

  String? accessToken;
  String? refreshToken;
  String? role;
  Map<String, dynamic> profile = const {};

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      accessToken = data['accessToken'] as String?;
      refreshToken = data['refreshToken'] as String?;
      role = data['role'] as String?;
      profile = Map<String, dynamic>.from(data['profile'] as Map? ?? const {});
    } catch (_) {
      await clear();
    }
  }

  Future<void> saveLogin(String access, String refresh, String role, Map<String, dynamic> profile) async {
    accessToken = access;
    refreshToken = refresh;
    this.role = role;
    this.profile = profile;
    await _persist();
  }

  Future<void> saveTokens(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    await _persist();
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    role = null;
    profile = const {};
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  Future<void> _persist() => _storage.write(
    key: _key,
    value: jsonEncode({'accessToken': accessToken, 'refreshToken': refreshToken, 'role': role, 'profile': profile}),
  );
}
