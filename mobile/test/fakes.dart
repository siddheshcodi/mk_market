import 'package:mk_market/core/api_client.dart';
import 'package:mk_market/core/token_store.dart';

typedef Handler = Object? Function(String method, String path, Object? body, Map<String, String>? query);

/// Answers API calls from a test-provided handler instead of the network.
class FakeApi extends ApiClient {
  FakeApi(this.handler, TokenStore tokens) : super('http://fake', tokens);

  Handler handler;
  final List<String> calls = [];

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    calls.add('GET $path');
    return handler('GET', path, null, query);
  }

  @override
  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) async {
    calls.add('POST $path');
    return handler('POST', path, body, null);
  }
}

/// Secure storage isn't available in widget tests.
class MemoryTokenStore extends TokenStore {
  @override
  Future<void> load() async {}

  @override
  Future<void> saveLogin(String access, String refresh, String role, Map<String, dynamic> profile) async {
    accessToken = access;
    refreshToken = refresh;
    this.role = role;
    this.profile = profile;
  }

  @override
  Future<void> saveTokens(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    role = null;
    profile = const {};
  }
}

ApiException apiError(int status, String code, String message, [Map<String, dynamic> details = const {}]) =>
    ApiException(status, code, message, details);
