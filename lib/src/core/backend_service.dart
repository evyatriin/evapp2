import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'app_config.dart';

class BackendService {
  static final _client = http.Client();

  // Cloud Run cold start can take ~5s; total budget 20s with one retry on 503.
  static const _timeout = Duration(seconds: 20);
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
    try {
      final response = await _client.get(uri, headers: headers).timeout(_timeout);
      if (response.statusCode == 503 && attempt < 2) {
        await Future<void>.delayed(_retryDelay);
        return _getWithRetry(endpoint, queryParams: queryParams, headers: headers, attempt: 2);
      }
      return _decode(response);
    } on TimeoutException {
      throw Exception('Request timed out. Check your connection and try again.');
    } catch (e) {
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
}
