import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'token_store.dart';

enum Role { user, storeManager, deliveryBoy }

extension RoleApi on Role {
  String get apiName => switch (this) {
    Role.user => 'USER',
    Role.storeManager => 'STORE_MANAGER',
    Role.deliveryBoy => 'DELIVERY_BOY',
  };

  String get label => switch (this) {
    Role.user => 'Customer',
    Role.storeManager => 'Store manager',
    Role.deliveryBoy => 'Delivery boy',
  };

  static Role? fromApi(String? name) => Role.values.where((r) => r.apiName == name).firstOrNull;
}

class OtpRequest {
  OtpRequest(this.requestId, this.resendAfterSec);
  final String requestId;
  final int resendAfterSec;
}

/// Who is logged in. The app shows the module for [role] and the login screens when it is null.
class Session extends ChangeNotifier {
  Session(this.api, this.tokens) {
    api.onSessionExpired = () {
      if (role != null) notifyListeners();
    };
  }

  final ApiClient api;
  final TokenStore tokens;
  bool restoring = true;

  Role? get role => tokens.accessToken == null ? null : RoleApi.fromApi(tokens.role);
  Map<String, dynamic> get profile => tokens.profile;

  Future<void> restore() async {
    await tokens.load();
    restoring = false;
    notifyListeners();
  }

  Future<OtpRequest> requestOtp(String mobile, Role role) async {
    final res = await api.post('/auth/otp/request', body: {'mobile': mobile, 'role': role.apiName});
    return OtpRequest(res['requestId'] as String, res['resendAfterSec'] as int);
  }

  Future<void> verifyOtp(String requestId, String otp, Role role) async {
    final res = await api.post('/auth/otp/verify', body: {'requestId': requestId, 'otp': otp}) as Map<String, dynamic>;
    final profile = (res['user'] ?? res['staff']) as Map<String, dynamic>;
    await tokens.saveLogin(res['accessToken'] as String, res['refreshToken'] as String, role.apiName, profile);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {
      // Logging out locally is enough if the server can't be reached.
    }
    await tokens.clear();
    notifyListeners();
  }
}
