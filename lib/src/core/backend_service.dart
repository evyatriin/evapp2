import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'connectivity_service.dart';
import 'result.dart';

class BackendService {
  static final _client = http.Client();

  // Route calculation calls external APIs (HERE routing, elevation, chargers) — needs 60s
  static const _timeout = Duration(seconds: 60);
  static const _retryDelay = Duration(seconds: 3);

  static String get baseUrl => AppConfig.backendBaseUrl;

  static Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) =>
      _getWithRetry(endpoint, queryParams: queryParams, headers: headers);

  static Future<dynamic> _getWithRetry(
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    int attempt = 1,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
    debugPrint('[BackendService] GET $uri (attempt $attempt)');
    try {
      final response = await _client.get(uri, headers: headers).timeout(_timeout);
      debugPrint('[BackendService] Response: ${response.statusCode} (${response.body.length} bytes)');
      if (response.statusCode == 503 && attempt < 2) {
        await Future<void>.delayed(_retryDelay);
        return _getWithRetry(endpoint, queryParams: queryParams, headers: headers, attempt: 2);
      }
      return _decode(response);
    } on TimeoutException {
      debugPrint('[BackendService] TIMEOUT: $uri');
      throw Exception('Request timed out. Check your connection and try again.');
    } catch (e) {
      debugPrint('[BackendService] ERROR: $uri => $e');
      throw Exception('Network Error: $e');
    }
  }

  static Future<dynamic> post(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) =>
      _postWithRetry(endpoint, body: body, headers: headers);

  static Future<dynamic> _postWithRetry(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    int attempt = 1,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (response.statusCode == 503 && attempt < 2) {
        await Future<void>.delayed(_retryDelay);
        return _postWithRetry(endpoint, body: body, headers: headers, attempt: 2);
      }
      return _decode(response);
    } on TimeoutException {
      throw Exception('Request timed out. Check your connection and try again.');
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }

  static Future<dynamic> put(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .put(
            uri,
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      return _decode(response);
    } on TimeoutException {
      throw Exception('Request timed out. Check your connection and try again.');
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }

  static Future<dynamic> delete(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await _client
          .delete(uri, headers: headers)
          .timeout(_timeout);
      if (response.statusCode == 204 || response.body.trim().isEmpty) {
        return null;
      }
      return _decode(response);
    } on TimeoutException {
      throw Exception('Request timed out. Check your connection and try again.');
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }

  static dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.trim().isEmpty) return null;
      return jsonDecode(response.body);
    }
    throw Exception('Backend Error: ${response.statusCode} - ${response.body}');
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
  }) async {
    final online = await checkConnectivityNow();
    if (!online) return Failure(AppError.offline());

    try {
      final data = await _getWithRetry(
        endpoint,
        queryParams: queryParams,
        headers: headers,
      );
      return Success(data);
    } on TimeoutException {
      return Failure(AppError.timeout());
    } on SocketException {
      return Failure(AppError.offline());
    } catch (e) {
      // If the error message looks like a server error, parse it
      final msg = e.toString();
      final match = RegExp(r'Backend Error: (\d+) - (.*)').firstMatch(msg);
      if (match != null) {
        return Failure(AppError.server(int.parse(match.group(1)!), match.group(2)!));
      }
      return Failure(AppError.unknown(e));
    }
  }

  /// POST that returns `Result<dynamic>` instead of throwing.
  static Future<Result<dynamic>> safePost(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    final online = await checkConnectivityNow();
    if (!online) return Failure(AppError.offline());

    try {
      final data = await _postWithRetry(endpoint, body: body, headers: headers);
      return Success(data);
    } on TimeoutException {
      return Failure(AppError.timeout());
    } on SocketException {
      return Failure(AppError.offline());
    } catch (e) {
      final msg = e.toString();
      final match = RegExp(r'Backend Error: (\d+) - (.*)').firstMatch(msg);
      if (match != null) {
        return Failure(AppError.server(int.parse(match.group(1)!), match.group(2)!));
      }
      return Failure(AppError.unknown(e));
    }
  }
}
