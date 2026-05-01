import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/backend_service.dart';
import 'station_model.dart';

class RemoteChargerService {
  Future<List<StationModel>> fetchRemoteStations(
    LatLng? center, {
    double radiusKm = 10.0,
  }) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      debugPrint('[RemoteChargerService] No auth token — user not logged in');
      return [];
    }

    final Map<String, String> queryParams = {};
    if (center != null) {
      queryParams['lat'] = center.latitude.toString();
      queryParams['lng'] = center.longitude.toString();
      queryParams['radius'] = radiusKm.toStringAsFixed(1);
    }

    // Throws on network/auth error — caller (stationsProvider) surfaces this
    // as AsyncError so the UI can show a retry button.
    final response = await BackendService.get(
      '/api/chargers/aggregate',
      queryParams: queryParams,
      headers: {'Authorization': 'Bearer $token'},
    );
    final List<dynamic> data = response as List<dynamic>;
    return data.map((json) => StationModel.fromJson(json)).toList();
  }
}
