import '../../core/backend_service.dart';

class SosService {
  Future<Map<String, dynamic>> sendSosAlert({
    required String userId,
    required double latitude,
    required double longitude,
    required String carModel,
    required String phoneNumber,
    String? message,
  }) async {
    try {
      final response = await BackendService.post('/api/sos/alert', body: {
        'user_id': userId,
        'latitude': latitude,
        'longitude': longitude,
        'car_model': carModel,
        'phone_number': phoneNumber,
        'message': message,
      });
      return response as Map<String, dynamic>; // Assuming backend returns the created alert
    } catch (e) {
      print('Error sending SOS: $e');
      throw e;
    }
  }

  Future<List<dynamic>> getNearbyAlerts(double lat, double lng) async {
    try {
      final response = await BackendService.get('/api/sos/nearby', queryParams: {
        'lat': lat.toString(),
        'long': lng.toString(),
      });
      return response as List<dynamic>;
    } catch (e) {
      print('Error fetching nearby alerts: $e');
      return [];
    }
  }
}
