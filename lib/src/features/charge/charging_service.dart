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

  Future<List<dynamic>> getCheckIns(String userId) async {
    try {
      final response = await BackendService.get('/api/chargers/checkins/$userId');
      return response as List<dynamic>;
    } catch (e) {
      print('Error fetching checkins: $e');
      return [];
    }
  }

  Future<void> submitCheckIn({
    required String userId,
    required String status,
    String? stationId,
    int? rating,
    String? comment,
    String? imageUrl,
  }) async {
    try {
      await BackendService.post('/api/chargers/checkin', body: {
        'user_id': userId,
        'station_id': stationId,
        'status': status,
        'rating': rating,
        'comment': comment,
        'image_url': imageUrl,
      });
    } catch (e) {
      print('Error submitting checkin: $e');
      throw e;
    }
  }

  // Saved Chargers Methods
  Future<List<dynamic>> getSavedChargers(String userId) async {
    try {
      final response = await BackendService.get('/api/chargers/saved/$userId');
      return response as List<dynamic>;
    } catch (e) {
      print('Error fetching saved chargers: $e');
      return [];
    }
  }

  Future<void> saveCharger({
    required String userId,
    required String stationId,
  }) async {
    try {
      await BackendService.post('/api/chargers/save', body: {
        'user_id': userId,
        'station_id': stationId,
      });
    } catch (e) {
      print('Error saving charger: $e');
      throw e;
    }
  }

  Future<void> unsaveCharger({
    required String userId,
    required String stationId,
  }) async {
    try {
      await BackendService.delete('/api/chargers/save/$userId/$stationId');
    } catch (e) {
      print('Error unsaving charger: $e');
      throw e;
    }
  }
}
