import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/charging_session_models.dart';
import '../../../core/app_config.dart';

class BecknChargingService {
  BecknChargingService({String? accessToken}) : _accessToken = accessToken;

  final String _baseUrl = AppConfig.backendBaseUrl;
  final String? _accessToken;

  static const _timeout = Duration(seconds: 15);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  String _extractDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['detail'] as String? ??
          body['message'] as String? ??
          response.body;
    } catch (_) {
      return response.body;
    }
  }

  void _assertSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backend error ${response.statusCode}: ${_extractDetail(response)}',
      );
    }
  }

  /// Search chargers near a location.
  Future<List<Map<String, dynamic>>> searchChargers({
    required double lat,
    required double lon,
    double radiusKm = 5.0,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/chargers/search',
    ).replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius_km': radiusKm.toString(),
      },
    );

    final response = await http
        .get(uri, headers: _headers)
        .timeout(_timeout);
    _assertSuccess(response);

    final data = jsonDecode(response.body);
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    // Some backends wrap in an object
    if (data is Map<String, dynamic> && data['chargers'] is List) {
      return (data['chargers'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Select a specific charger connector to get full details.
  Future<ChargerDetails> selectCharger({
    required String chargerId,
    required String connectorId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/chargers/$chargerId/connectors/$connectorId',
    );

    final response = await http
        .get(uri, headers: _headers)
        .timeout(_timeout);
    _assertSuccess(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ChargerDetails.fromJson(data);
  }

  /// Start a charging session. Returns the new sessionId.
  Future<String> startSession(SessionStartRequest request) async {
    final uri = Uri.parse('$_baseUrl/api/chargers/sessions/start');

    final response = await http
        .post(
          uri,
          headers: _headers,
          body: jsonEncode(request.toJson()),
        )
        .timeout(_timeout);
    _assertSuccess(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sessionId = data['session_id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw Exception('Backend did not return a session_id');
    }
    return sessionId;
  }

  /// Get the current status of a charging session.
  Future<Map<String, dynamic>> getSessionStatus(String sessionId) async {
    final uri = Uri.parse('$_baseUrl/api/chargers/sessions/$sessionId/status');

    final response = await http
        .get(uri, headers: _headers)
        .timeout(_timeout);
    _assertSuccess(response);

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// End a charging session. Returns payment data including UPI URI.
  Future<Map<String, dynamic>> endSession(String sessionId) async {
    final uri = Uri.parse('$_baseUrl/api/chargers/sessions/$sessionId/end');

    final response = await http
        .post(
          uri,
          headers: _headers,
          body: jsonEncode(<String, dynamic>{'session_id': sessionId}),
        )
        .timeout(_timeout);
    _assertSuccess(response);

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Confirm payment for a completed session.
  Future<void> confirmPayment({
    required String sessionId,
    required String referenceId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/chargers/sessions/$sessionId/confirm-payment',
    );

    final response = await http
        .post(
          uri,
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'session_id': sessionId,
            'reference_id': referenceId,
          }),
        )
        .timeout(_timeout);
    _assertSuccess(response);
  }

  /// Fetch remote feature flags.
  Future<Map<String, dynamic>> getFeatureFlags() async {
    final uri = Uri.parse('$_baseUrl/api/chargers/feature-flags');

    final response = await http
        .get(uri, headers: _headers)
        .timeout(_timeout);
    _assertSuccess(response);

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
