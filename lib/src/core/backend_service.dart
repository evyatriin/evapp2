import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class BackendService {
  // Use 10.0.2.2 for Android Emulator, localhost for iOS Simulator
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    } else {
      return 'http://127.0.0.1:8000';
    }
  }

  static Future<dynamic> get(String endpoint, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$baseUrl$endpoint').replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Backend Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }

  static Future<dynamic> post(String endpoint, {required Map<String, dynamic> body}) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Backend Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }
}
