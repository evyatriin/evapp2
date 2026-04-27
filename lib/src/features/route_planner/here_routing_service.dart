import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../core/backend_service.dart';
import '../vehicle_profile/vehicle_model.dart';
import 'route_model.dart';

class HereRoutingService {
  Future<List<RouteModel>> calculateEVRoutes({
    required LatLng origin,
    required LatLng destination,
    required int currentSoc,
    required int targetSoc,
    required int soh,
    VehicleProfile? vehicle,
    bool isRoundTrip = false,
    int shortStayDurationMin = 0,
  }) async {
    try {
      final estimatedRangeKm = vehicle?.estimatedRange;
      final response = await BackendService.post(
        '/api/route/',
        body: {
          'origin': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
          'destination': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
          'current_soc': currentSoc,
          'target_soc': targetSoc,
          'soh': soh,
          'is_round_trip': isRoundTrip,
          'short_stay_duration_min': shortStayDurationMin,
          if (vehicle != null)
            'vehicle': {
              'brand': vehicle.brand,
              'model': vehicle.model,
              'variant': vehicle.variant,
              'range_efficiency': vehicle.rangeEfficiency,
              'preferred_charging_networks': vehicle.preferredChargingNetworks,
              if (estimatedRangeKm != null) 'estimated_range_km': estimatedRangeKm,
            },
        },
      );

      if (response is! List) {
        throw Exception('Unexpected route response from server');
      }

      final routes =
          response
              .cast<Map<String, dynamic>>()
              .map(RouteModel.fromJson)
              .toList();

      if (routes.isEmpty) {
        throw Exception(
          'No route options were returned. Try different locations or charge settings.',
        );
      }

      return routes;
    } catch (e) {
      debugPrint('Error calculating routes via backend: $e');
      throw Exception('Could not plan trip: $e');
    }
  }
}
