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

  Future<Map<String, dynamic>?> getLatestStationCheckIn(String stationId) async {
    try {
      final response = await BackendService.get('/api/chargers/checkin/station/$stationId/latest');
      if (response != null) {
        return response as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('Error fetching latest station checkin: $e');
      return null;
    }
  }

  Future<List<dynamic>> getPublicCheckIns({int limit = 50}) async {
    try {
      final response = await BackendService.get('/api/chargers/checkins/public?limit=$limit');
      return response as List<dynamic>;
    } catch (e) {
      print('Error fetching public checkins: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> voteCheckIn({
    required String userId,
    required String checkinId,
    required String voteType, // "upvote" or "downvote"
  }) async {
    try {
      final response = await BackendService.post('/api/chargers/checkin/vote', body: {
        'user_id': userId,
        'checkin_id': checkinId,
        'vote_type': voteType,
      });
      return response as Map<String, dynamic>;
    } catch (e) {
      print('Error voting on checkin: $e');
      return null;
    }
  }

  Future<void> submitCheckIn({
    required String userId,
    required String status,
    String? stationId,
    int? rating,
    String? comment,
    String? imageUrl,
    int? batteryStartPercent,
    int? batteryEndPercent,
    int? timeTakenMinutes,
    double? costPaid,
    String? chargingSlipUrl,
    int? pointsEarned,
    String? userName,
  }) async {
    try {
      await BackendService.post('/api/chargers/checkin', body: {
        'user_id': userId,
        'station_id': stationId,
        'status': status,
        'rating': rating,
        'comment': comment,
        'image_url': imageUrl,
        'battery_start_percent': batteryStartPercent,
        'battery_end_percent': batteryEndPercent,
        'time_taken_minutes': timeTakenMinutes,
        'cost_paid': costPaid,
        'charging_slip_url': chargingSlipUrl,
        'points_earned': pointsEarned,
        'user_name': userName,
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
