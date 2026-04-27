import 'package:flutter/foundation.dart';

import '../../core/backend_service.dart';
import '../authentication/auth_service.dart';

class HostChargerListing {
  final String id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final List<String> connectorTypes;
  final double? powerKw;
  final String hostName;
  final String hostPhone;
  final String? hostUpiId;
  final double? pricePerKwh;
  final double? pricePerSession;
  final String? availableFrom;
  final String? availableTo;
  final List<String> availableDays;
  final bool isAcceptingRequests;
  final String? accessInstructions;
  final String? parkingNotes;
  final String? houseRules;

  const HostChargerListing({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.hostName,
    required this.hostPhone,
    this.connectorTypes = const [],
    this.powerKw,
    this.address,
    this.hostUpiId,
    this.pricePerKwh,
    this.pricePerSession,
    this.availableFrom,
    this.availableTo,
    this.availableDays = const [],
    this.isAcceptingRequests = false,
    this.accessInstructions,
    this.parkingNotes,
    this.houseRules,
  });

  factory HostChargerListing.fromJson(Map<String, dynamic> json) {
    return HostChargerListing(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Hosted Charger',
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      connectorTypes: List<String>.from(json['connector_types'] ?? const []),
      powerKw: (json['power_kw'] as num?)?.toDouble(),
      hostName: json['host_name'] as String? ?? '',
      hostPhone: json['host_phone'] as String? ?? '',
      hostUpiId: json['host_upi_id'] as String?,
      pricePerKwh: (json['price_per_kwh'] as num?)?.toDouble(),
      pricePerSession: (json['price_per_session'] as num?)?.toDouble(),
      availableFrom: json['available_from'] as String?,
      availableTo: json['available_to'] as String?,
      availableDays: List<String>.from(json['available_days'] ?? const []),
      isAcceptingRequests: json['is_accepting_requests'] == true,
      accessInstructions: json['access_instructions'] as String?,
      parkingNotes: json['parking_notes'] as String?,
      houseRules: json['house_rules'] as String?,
    );
  }
}

class ChargerRequestItem {
  final String id;
  final String stationId;
  final String status;
  final String? requesterName;
  final String? requesterPhone;
  final String? vehicleName;
  final int? currentSoc;
  final String? message;
  final DateTime? requestedStartAt;
  final DateTime? requestedEndAt;
  final double? estimatedAmount;
  final String? hostResponse;
  final Map<String, dynamic>? station;
  final Map<String, dynamic>? hostContact;

  const ChargerRequestItem({
    required this.id,
    required this.stationId,
    required this.status,
    this.requesterName,
    this.requesterPhone,
    this.vehicleName,
    this.currentSoc,
    this.message,
    this.requestedStartAt,
    this.requestedEndAt,
    this.estimatedAmount,
    this.hostResponse,
    this.station,
    this.hostContact,
  });

  factory ChargerRequestItem.fromJson(Map<String, dynamic> json) {
    return ChargerRequestItem(
      id: json['id']?.toString() ?? '',
      stationId: json['station_id']?.toString() ?? '',
      status: json['status'] as String? ?? 'pending',
      requesterName: json['requester_name'] as String?,
      requesterPhone: json['requester_phone'] as String?,
      vehicleName: json['vehicle_name'] as String?,
      currentSoc: json['current_soc'] as int?,
      message: json['message'] as String?,
      requestedStartAt: json['requested_start_at'] != null
          ? DateTime.tryParse(json['requested_start_at'] as String)
          : null,
      requestedEndAt: json['requested_end_at'] != null
          ? DateTime.tryParse(json['requested_end_at'] as String)
          : null,
      estimatedAmount: (json['estimated_amount'] as num?)?.toDouble(),
      hostResponse: json['host_response'] as String?,
      station: json['station'] is Map<String, dynamic>
          ? json['station'] as Map<String, dynamic>
          : json['station'] is Map
          ? Map<String, dynamic>.from(json['station'] as Map)
          : null,
      hostContact: json['host_contact'] is Map<String, dynamic>
          ? json['host_contact'] as Map<String, dynamic>
          : json['host_contact'] is Map
          ? Map<String, dynamic>.from(json['host_contact'] as Map)
          : null,
    );
  }
}

class ChargingService {
  final _authService = AuthService();

  Future<List<dynamic>> getChargingHistory(String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chargers/history/$userId',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching charging history: $e');
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
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to log a charging session.');
    }

    try {
      await BackendService.post(
        '/api/chargers/session',
        body: {
          'user_id': userId,
          'station_id': stationId,
          'start_time': startTime.toIso8601String(),
          'kwh_added': kwhAdded,
          'cost': cost,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Error logging session: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> getCheckIns(String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chargers/checkins/$userId',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching checkins: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestStationCheckIn(
    String stationId,
  ) async {
    try {
      final response = await BackendService.get(
        '/api/chargers/checkin/station/$stationId/latest',
      );
      if (response != null) {
        return response as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching latest station checkin: $e');
      return null;
    }
  }

  Future<List<dynamic>> getPublicCheckIns({int limit = 50}) async {
    try {
      final response = await BackendService.get(
        '/api/chargers/checkins/public?limit=$limit',
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching public checkins: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> voteCheckIn({
    required String userId,
    required String checkinId,
    required String voteType, // "upvote" or "downvote"
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) return null;

    try {
      final response = await BackendService.post(
        '/api/chargers/checkin/vote',
        body: {
          'user_id': userId,
          'checkin_id': checkinId,
          'vote_type': voteType,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error voting on checkin: $e');
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
    // Electric Talks trip context
    String? weather,
    String? tripType,
    int? passengerCount,
    String? driveMode,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to submit a check-in.');
    }

    try {
      await BackendService.post(
        '/api/chargers/checkin',
        body: {
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
          'weather': weather,
          'trip_type': tripType,
          'passenger_count': passengerCount,
          'drive_mode': driveMode,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Error submitting checkin: $e');
      rethrow;
    }
  }

  // Saved Chargers Methods
  Future<List<dynamic>> getSavedChargers(String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chargers/saved/$userId',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching saved chargers: $e');
      return [];
    }
  }

  Future<void> saveCharger({
    required String userId,
    required String stationId,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to save a charger.');
    }

    try {
      await BackendService.post(
        '/api/chargers/save',
        body: {'user_id': userId, 'station_id': stationId},
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Error saving charger: $e');
      rethrow;
    }
  }

  Future<void> unsaveCharger({
    required String userId,
    required String stationId,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to remove a saved charger.');
    }

    try {
      await BackendService.delete(
        '/api/chargers/save/$userId/$stationId',
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Error unsaving charger: $e');
      rethrow;
    }
  }

  Future<List<HostChargerListing>> getHostedChargers(String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chargers/hosted/$userId',
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response as List<dynamic>;
      return data
          .map((item) => HostChargerListing.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching hosted chargers: $e');
      return [];
    }
  }

  Future<HostChargerListing?> saveHostedCharger({
    String? stationId,
    required String ownerId,
    required String name,
    required double latitude,
    required double longitude,
    String? address,
    String? provider,
    List<String> connectorTypes = const [],
    double? powerKw,
    double? pricePerKwh,
    double? pricePerSession,
    required String hostName,
    required String hostPhone,
    String? hostUpiId,
    String? accessInstructions,
    String? availableFrom,
    String? availableTo,
    List<String> availableDays = const [],
    String? parkingNotes,
    String? houseRules,
    bool isAcceptingRequests = true,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to host a charger.');
    }

    try {
      final response = await BackendService.post(
        '/api/chargers/host',
        body: {
          'station_id': stationId,
          'owner_id': ownerId,
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'provider': provider,
          'connector_types': connectorTypes,
          'power_kw': powerKw,
          'price_per_kwh': pricePerKwh,
          'price_per_session': pricePerSession,
          'host_name': hostName,
          'host_phone': hostPhone,
          'host_upi_id': hostUpiId,
          'access_instructions': accessInstructions,
          'available_from': availableFrom,
          'available_to': availableTo,
          'available_days': availableDays,
          'parking_notes': parkingNotes,
          'house_rules': houseRules,
          'is_accepting_requests': isAcceptingRequests,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      return HostChargerListing.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      debugPrint('Error saving hosted charger: $e');
      rethrow;
    }
  }

  Future<ChargerRequestItem?> createChargerRequest({
    required String stationId,
    required String requesterUserId,
    String? requesterName,
    required String requesterPhone,
    String? vehicleName,
    int? currentSoc,
    String? message,
    required DateTime requestedStartAt,
    DateTime? requestedEndAt,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to request charging.');
    }

    try {
      final response = await BackendService.post(
        '/api/chargers/request',
        body: {
          'station_id': stationId,
          'requester_user_id': requesterUserId,
          'requester_name': requesterName,
          'requester_phone': requesterPhone,
          'vehicle_name': vehicleName,
          'current_soc': currentSoc,
          'message': message,
          'requested_start_at': requestedStartAt.toIso8601String(),
          'requested_end_at': requestedEndAt?.toIso8601String(),
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      return ChargerRequestItem.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      debugPrint('Error creating charger request: $e');
      rethrow;
    }
  }

  Future<List<ChargerRequestItem>> getIncomingRequests(String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chargers/requests/incoming/$userId',
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response as List<dynamic>;
      return data
          .map((item) => ChargerRequestItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching incoming charger requests: $e');
      return [];
    }
  }

  Future<List<ChargerRequestItem>> getOutgoingRequests(String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chargers/requests/outgoing/$userId',
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response as List<dynamic>;
      return data
          .map((item) => ChargerRequestItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching outgoing charger requests: $e');
      return [];
    }
  }

  Future<ChargerRequestItem?> decideChargerRequest({
    required String requestId,
    required String hostUserId,
    required String status,
    String? hostResponse,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to manage charger requests.');
    }

    try {
      final response = await BackendService.post(
        '/api/chargers/request/$requestId/decision',
        body: {
          'host_user_id': hostUserId,
          'status': status,
          'host_response': hostResponse,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      return ChargerRequestItem.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      debugPrint('Error deciding charger request: $e');
      rethrow;
    }
  }

  Future<ChargerRequestItem?> completeChargerRequest({
    required String requestId,
    required String hostUserId,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to complete charger requests.');
    }

    try {
      final response = await BackendService.post(
        '/api/chargers/request/$requestId/complete',
        body: {'host_user_id': hostUserId},
        headers: {'Authorization': 'Bearer $token'},
      );
      return ChargerRequestItem.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      debugPrint('Error completing charger request: $e');
      rethrow;
    }
  }
}
