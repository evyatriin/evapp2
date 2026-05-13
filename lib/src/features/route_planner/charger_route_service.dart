import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../core/backend_service.dart';
import 'charger_along_route_model.dart';

class ChargerRouteService {
  /// Fetch all chargers along a route with distances from origin
  ///
  /// Parameters:
  /// - origin: Starting location
  /// - destination: Ending location
  /// - polyline: Route polyline points (optional, if not provided will use direct line)
  /// - radiusKm: Search radius around the route (default: 20km)
  Future<List<ChargerAlongRoute>> getChargersAlongRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? polyline,
    double radiusKm = 20.0,
  }) async {
    try {
      final response = await BackendService.post(
        '/api/chargers/along-route',
        body: {
          'origin_lat': origin.latitude,
          'origin_lng': origin.longitude,
          'destination_lat': destination.latitude,
          'destination_lng': destination.longitude,
          'radius_km': radiusKm,
          if (polyline != null && polyline.isNotEmpty)
            'polyline': polyline
                .map((p) => {
                  'latitude': p.latitude,
                  'longitude': p.longitude,
                })
                .toList(),
        },
      );

      debugPrint('Chargers along route response: $response');

      if (response is! List) {
        debugPrint('Unexpected response type for chargers along route: ${response.runtimeType}');
        return [];
      }

      final chargers = response
          .cast<Map<String, dynamic>>()
          .map((chargerJson) {
            debugPrint('Parsing charger: $chargerJson');
            return ChargerAlongRoute.fromJson(chargerJson);
          })
          .toList();

      debugPrint('Successfully parsed ${chargers.length} chargers along route');

      // Log charger types
      final optimalCount = chargers.where((c) => c.isOptimal).length;
      final alternativeCount = chargers.where((c) => !c.isOptimal).length;
      debugPrint('Chargers breakdown - Optimal: $optimalCount, Alternative: $alternativeCount');

      return chargers;
    } catch (e) {
      debugPrint('Error fetching chargers along route: $e');
      return [];
    }
  }

  /// Get only optimal chargers (those on the recommended route)
  Future<List<ChargerAlongRoute>> getOptimalChargersAlongRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? polyline,
  }) async {
    try {
      final allChargers = await getChargersAlongRoute(
        origin: origin,
        destination: destination,
        polyline: polyline,
      );

      return allChargers.where((c) => c.isOptimal).toList();
    } catch (e) {
      debugPrint('Error fetching optimal chargers: $e');
      return [];
    }
  }

  /// Get nearby alternative chargers
  Future<List<ChargerAlongRoute>> getAlternativeChargersAlongRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? polyline,
    double radiusKm = 20.0,
  }) async {
    try {
      final allChargers = await getChargersAlongRoute(
        origin: origin,
        destination: destination,
        polyline: polyline,
        radiusKm: radiusKm,
      );

      return allChargers.where((c) => !c.isOptimal).toList();
    } catch (e) {
      debugPrint('Error fetching alternative chargers: $e');
      return [];
    }
  }
}
