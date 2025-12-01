
import 'package:latlong2/latlong.dart';
import '../../core/backend_service.dart';
import 'route_model.dart';

class HereRoutingService {

  Future<List<RouteModel>> calculateEVRoutes({
    required LatLng origin,
    required LatLng destination,
    required int currentSoc,
    required int targetSoc,
    required int soh,
    bool isRoundTrip = false,
    int shortStayDurationMin = 0,
  }) async {
    try {
      final response = await BackendService.post('/api/route/', body: {
        'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
        'destination': {'latitude': destination.latitude, 'longitude': destination.longitude},
        'current_soc': currentSoc,
        'target_soc': targetSoc,
        'soh': soh,
        'is_round_trip': isRoundTrip,
        'short_stay_duration_min': shortStayDurationMin,
      });

      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => RouteModel.fromJson(json)).toList();
    } catch (e) {
      print('Error calculating routes via backend: $e');
      return [];
    }
  }

  RouteModel _createDummyRoute({
    required String id,
    required String name,
    required LatLng origin,
    required LatLng destination,
    required double distanceKm,
    required double durationMin,
    required int stops,
    required double colorOffset,
  }) {
    // Generate a simple straight line polyline with some jitter
    final List<LatLng> polyline = [];
    const int points = 20;
    for (int i = 0; i <= points; i++) {
      final double t = i / points;
      final double lat = origin.latitude + (destination.latitude - origin.latitude) * t + (i % 2 == 0 ? colorOffset : -colorOffset);
      final double lng = origin.longitude + (destination.longitude - origin.longitude) * t + (i % 2 != 0 ? colorOffset : -colorOffset);
      polyline.add(LatLng(lat, lng));
    }

    final List<RouteStop> routeStops = [];
    routeStops.add(RouteStop(
      name: 'Start',
      location: origin,
      type: StopType.origin,
      arrivalTime: DateTime.now(),
    ));

    // Add dummy charging stops
    for (int i = 1; i <= stops; i++) {
       final double t = i / (stops + 1);
       final double lat = origin.latitude + (destination.latitude - origin.latitude) * t;
       final double lng = origin.longitude + (destination.longitude - origin.longitude) * t;
       
       routeStops.add(RouteStop(
        name: 'Charging Station $i',
        location: LatLng(lat, lng),
        type: StopType.charging,
        arrivalTime: DateTime.now().add(Duration(minutes: (durationMin * t).round())),
        chargeDurationMin: 30,
        targetSoc: 80,
      ));
    }

    routeStops.add(RouteStop(
      name: 'Destination',
      location: destination,
      type: StopType.destination,
      arrivalTime: DateTime.now().add(Duration(minutes: durationMin.round())),
    ));

    return RouteModel(
      id: id,
      name: name,
      polyline: polyline,
      totalDistanceKm: distanceKm,
      totalDurationMin: durationMin,
      stops: routeStops,
      estimatedCost: distanceKm * 2.5, // Rough calc
    );
  }
}
