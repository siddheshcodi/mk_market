import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// An error from the API, using its { error: { code, message } } body, or a network problem.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details = const {}]);

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  /// Field names the server rejected, e.g. ["pincode", "city"].
  List<String> get fields => (details['fields'] as List?)?.cast<String>() ?? const [];

  @override
  String toString() => message;
}

/// JSON client for /api/v1. Adds the access token and refreshes it once when it has expired.
class ApiClient {
  ApiClient(this.baseUrl, this.tokens);

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http = http.Client();

  /// Called when the session can't be refreshed, so the app can go back to login.
  void Function()? onSessionExpired;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) =>
      _send('POST', path, body: body, headers: headers);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['content-type'] = 'application/json'
      ..headers.addAll(headers ?? const {});
    final access = tokens.accessToken;
    if (access != null) request.headers['authorization'] = 'Bearer $access';
    if (body != null) request.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
    } on TimeoutException {
      throw ApiException(0, 'NETWORK', 'The server is taking too long. Please try again.');
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'No connection. Please check your internet and try again.');
    }

    if (res.statusCode == 401 && !retried && !path.startsWith('/auth/') && await _refresh()) {
      return _send(method, path, query: query, body: body, headers: headers, retried: true);
    }

    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is Map && decoded['error'] is Map) {
      final error = Map<String, dynamic>.from(decoded['error'] as Map);
      if (res.statusCode == 401 && !path.startsWith('/auth/otp')) _expire();
      throw ApiException(
        res.statusCode,
        error['code'] as String? ?? 'ERROR',
        error['message'] as String? ?? 'Something went wrong. Please try again.',
        error,
      );
    }
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, 'ERROR', 'Something went wrong. Please try again.');
    }
    return decoded;
  }

  Future<bool> _refresh() async {
    final refresh = tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await _http
          .post(
            Uri.parse('$baseUrl/auth/token/refresh'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        _expire();
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await tokens.saveTokens(body['accessToken'] as String, body['refreshToken'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _expire() {
    tokens.clear();
    onSessionExpired?.call();
  }
}
