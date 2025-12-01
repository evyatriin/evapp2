import '../../core/backend_service.dart';

class ChargingService {
  Future<List<dynamic>> getChargingHistory(String userId) async {
    try {
      final response = await BackendService.get('/api/chargers/history/$userId');
      return response as List<dynamic>;
    } catch (e) {
      print('Error fetching charging history: $e');
      return [];
    }
  }

  Future<void> logSession({
    required String userId,
    required String stationId,
    required DateTime startTime,
    required double kwhAdded,
    required double cost,
  }) async {
    try {
      await BackendService.post('/api/chargers/session', body: {
        'user_id': userId,
        'station_id': stationId,
        'start_time': startTime.toIso8601String(),
        'kwh_added': kwhAdded,
        'cost': cost,
      });
    } catch (e) {
      print('Error logging session: $e');
      throw e;
    }
  }
}
