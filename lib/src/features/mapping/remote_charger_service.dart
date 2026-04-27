import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../core/backend_service.dart';
import 'station_model.dart';

class RemoteChargerService {
  Future<List<StationModel>> fetchRemoteStations(
    LatLng? center, {
    double radiusKm = 10.0,
  }) async {
    try {
      final Map<String, String> queryParams = {};
      if (center != null) {
        queryParams['lat'] = center.latitude.toString();
        queryParams['lng'] = center.longitude.toString();
        queryParams['radius'] = radiusKm.toStringAsFixed(1);
      }

      final response = await BackendService.get(
        '/api/chargers/aggregate',
        queryParams: queryParams,
      );
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => StationModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching remote stations via backend: $e');
      return [];
    }
  }
}
