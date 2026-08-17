import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/charging_session_models.dart';
import '../../../core/app_config.dart';

class QRScannerService {
  QRScannerService({String? accessToken}) : _accessToken = accessToken;

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

  /// Validate a scanned QR code and return the charger details.
  /// POST /api/chargers/qr/validate
  Future<ChargerDetails> validateQRCode(String qrData) async {
    final uri = Uri.parse('$_baseUrl/api/chargers/qr/validate');

    final response = await http
        .post(
          uri,
          headers: _headers,
          body: jsonEncode(<String, dynamic>{'qr_data': qrData}),
        )
        .timeout(_timeout);
    _assertSuccess(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ChargerDetails.fromJson(data);
  }

  /// Fetch the base64-encoded QR code image for a charger.
  /// GET /api/chargers/{id}/qr
  Future<String> getChargerQRCode(String chargerId) async {
    final uri = Uri.parse('$_baseUrl/api/chargers/$chargerId/qr');

    final response = await http
        .get(uri, headers: _headers)
        .timeout(_timeout);
    _assertSuccess(response);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final qrCode = data['qr_code'] as String?;
    if (qrCode == null || qrCode.isEmpty) {
      throw Exception('Backend did not return a qr_code field');
    }
    return qrCode;
  }
}
