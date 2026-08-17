import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';
import 'connectivity_service.dart';
import 'result.dart';

class BackendException implements Exception {
  const BackendException({
    required this.statusCode,
    required this.message,
    this.code,
    this.fieldErrors,
  });

  final int statusCode;
  final String message;
  final String? code;
  final Map<String, dynamic>? fieldErrors;

  @override
  String toString() => message;
}

class BackendService {
  static final http.Client _client = http.Client();
  static const Duration _timeout = Duration(seconds: 60);
  static const Duration _retryDelay = Duration(seconds: 2);

  static String get baseUrl => AppConfig.backendBaseUrl;

  static Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool authenticated = true,
  }) {
    final uri = Uri.parse(
      '$baseUrl$endpoint',
    ).replace(queryParameters: queryParams);
    return _send(
      () async => _client.get(
        uri,
        headers: await _headers(headers, authenticated: authenticated),
      ),
      authenticated: authenticated,
    );
  }

  static Future<dynamic> post(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    bool authenticated = true,
  }) {
    final uri = Uri.parse('$baseUrl$endpoint');
    return _send(
      () async => _client.post(
        uri,
        headers: await _headers({
          'Content-Type': 'application/json',
          ...?headers,
        }, authenticated: authenticated),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
  }

  static Future<dynamic> put(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    bool authenticated = true,
  }) {
    final uri = Uri.parse('$baseUrl$endpoint');
    return _send(
      () async => _client.put(
        uri,
        headers: await _headers({
          'Content-Type': 'application/json',
          ...?headers,
        }, authenticated: authenticated),
        body: jsonEncode(body),
      ),
      authenticated: authenticated,
    );
  }

  static Future<dynamic> delete(
    String endpoint, {
    Map<String, String>? headers,
    bool authenticated = true,
  }) {
    final uri = Uri.parse('$baseUrl$endpoint');
    return _send(
      () async => _client.delete(
        uri,
        headers: await _headers(headers, authenticated: authenticated),
      ),
      authenticated: authenticated,
    );
  }

  static Future<Map<String, String>> _headers(
    Map<String, String>? headers, {
    required bool authenticated,
  }) async {
    final result = <String, String>{...?headers};
    if (!authenticated || result.containsKey('Authorization')) return result;

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      result['Authorization'] = 'Bearer ${session.accessToken}';
    }
    return result;
  }

  static Future<dynamic> _send(
    Future<http.Response> Function() request, {
    required bool authenticated,
  }) async {
    try {
      var response = await request().timeout(_timeout);

      if (response.statusCode == 401 && authenticated) {
        final currentSession = Supabase.instance.client.auth.currentSession;
        if (currentSession != null) {
          try {
            await Supabase.instance.client.auth.refreshSession();
            response = await request().timeout(_timeout);
          } on AuthException {
            await Supabase.instance.client.auth.signOut(
              scope: SignOutScope.local,
            );
          }
        }
      }

      if (response.statusCode == 503) {
        await Future<void>.delayed(_retryDelay);
        response = await request().timeout(_timeout);
      }

      return _decode(response);
    } on BackendException {
      rethrow;
    } on TimeoutException {
      throw const BackendException(
        statusCode: 408,
        message: 'The request timed out. Check your connection and try again.',
      );
    } on AuthException {
      throw const BackendException(
        statusCode: 401,
        message: 'Your session expired. Please sign in again.',
      );
    } catch (_) {
      throw const BackendException(
        statusCode: 0,
        message:
            'Unable to reach EVraahein. Check your connection and try again.',
      );
    }
  }

  static dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) return null;
      return jsonDecode(response.body);
    }

    String message = 'Something went wrong. Please try again.';
    String? code;
    Map<String, dynamic>? fieldErrors;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.isNotEmpty) message = detail;
        if (decoded['message'] is String) {
          message = decoded['message'] as String;
        }
        code = decoded['code'] as String?;
        fieldErrors = decoded['field_errors'] as Map<String, dynamic>?;
      }
    } catch (_) {
      // Keep the generic user-safe message for non-JSON upstream errors.
    }

    throw BackendException(
      statusCode: response.statusCode,
      message: message,
      code: code,
      fieldErrors: fieldErrors,
    );
  }

  // ── Safe variants returning Result<T> ─────────────────────────────────────
  //
  // Use these when you want to handle offline / error states without try/catch
  // at the call site, e.g. in services that back cached screens.
  //
  // The old throwing `get/post/put/delete` are kept for backward compatibility.

  /// GET that returns `Result<dynamic>` instead of throwing.
  /// Checks connectivity first; returns `Failure(AppError.offline())` immediately
  /// when the device has no network, so callers can fall back to cache.
  static Future<Result<dynamic>> safeGet(
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    final online = await checkConnectivityNow();
    if (!online) return Failure(AppError.offline());

    try {
      final data = await get(
        endpoint,
        queryParams: queryParams,
        headers: headers,
        authenticated: authenticated,
      );
      return Success(data);
    } on BackendException catch (e) {
      if (e.statusCode == 408) return Failure(AppError.timeout());
      if (e.statusCode == 0) return Failure(AppError.offline());
      return Failure(AppError.server(e.statusCode, e.message));
    } on SocketException {
      return Failure(AppError.offline());
    } catch (e) {
      return Failure(AppError.unknown(e));
    }
  }

  /// POST that returns `Result<dynamic>` instead of throwing.
  static Future<Result<dynamic>> safePost(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    final online = await checkConnectivityNow();
    if (!online) return Failure(AppError.offline());

    try {
      final data = await post(
        endpoint,
        body: body,
        headers: headers,
        authenticated: authenticated,
      );
      return Success(data);
    } on BackendException catch (e) {
      if (e.statusCode == 408) return Failure(AppError.timeout());
      if (e.statusCode == 0) return Failure(AppError.offline());
      return Failure(AppError.server(e.statusCode, e.message));
    } on SocketException {
      return Failure(AppError.offline());
    } catch (e) {
      return Failure(AppError.unknown(e));
    }
  }
}
