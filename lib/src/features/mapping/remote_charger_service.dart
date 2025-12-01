import 'package:latlong2/latlong.dart';
import '../../core/backend_service.dart';
import 'station_model.dart';

class RemoteChargerService {
  // Simulating a remote API call
  Future<List<StationModel>> fetchRemoteStations(LatLng? center) async {
    try {
      final Map<String, String> queryParams = {};
      if (center != null) {
        queryParams['lat'] = center.latitude.toString();
        queryParams['lng'] = center.longitude.toString();
      }

      final response = await BackendService.get('/api/chargers/', queryParams: queryParams);
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => StationModel.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching remote stations via backend: $e');
      return [];
    }
  }
}
