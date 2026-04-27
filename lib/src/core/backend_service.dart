import 'dart:convert';
import 'package:http/http.dart' as http;

import 'app_config.dart';

class BackendService {
  static String get baseUrl {
    return AppConfig.backendBaseUrl;
  }

  static Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(
      '$baseUrl$endpoint',
    ).replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
          'Backend Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }

  static Future<dynamic> post(
    String endpoint, {
    required Map<String, dynamic> body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
          'Backend Error: ${response.statusCode} - ${response.body}',
        );
      }
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
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json', ...?headers},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
          'Backend Error: ${response.statusCode} - ${response.body}',
        );
      }
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
      final response = await http.delete(uri, headers: headers);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 204 || response.body.trim().isEmpty) {
        return null;
      } else {
        throw Exception(
          'Backend Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }
}
