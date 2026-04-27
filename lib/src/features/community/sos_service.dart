import 'package:flutter/foundation.dart';

import '../../core/backend_service.dart';
import '../authentication/auth_service.dart';

class SosService {
  final _authService = AuthService();

  Future<Map<String, dynamic>> sendSosAlert({
    required String userId,
    required double latitude,
    required double longitude,
    required String carModel,
    required String phoneNumber,
    String? message,
  }) async {
    try {
      final response = await BackendService.post(
        '/api/sos/alert',
        body: {
          'user_id': userId,
          'latitude': latitude,
          'longitude': longitude,
          'car_model': carModel,
          'phone_number': phoneNumber,
          'message': message,
        },
        headers: {
          if (_authService.getAuthToken() case final token?) 'Authorization': 'Bearer $token',
        },
      );
      return response
          as Map<String, dynamic>; // Assuming backend returns the created alert
    } catch (e) {
      debugPrint('Error sending SOS: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getNearbyAlerts(double lat, double lng) async {
    try {
      final response = await BackendService.get(
        '/api/sos/nearby',
        queryParams: {'lat': lat.toString(), 'long': lng.toString()},
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching nearby alerts: $e');
      return [];
    }
  }
}
