import 'vehicle_model.dart';
import 'vehicle_template_model.dart';
import '../../core/backend_service.dart';
import '../authentication/auth_service.dart';

class VehicleService {
  final _authService = AuthService();

  /// Get current user ID from auth service
  String? getCurrentUserId() {
    return _authService.currentUserId;
  }

  /// Fetch all vehicles for a user from the backend
  Future<List<VehicleProfile>> fetchVehicles(String userId) async {
    try {
      final response = await BackendService.get(
        '/api/vehicles/',
        queryParams: {'user_id': userId},
      );
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => VehicleProfile.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching vehicles: $e');
      return [];
    }
  }

  /// Add a new vehicle to the backend
  Future<VehicleProfile?> addVehicle(VehicleProfile vehicle) async {
    try {
      final response = await BackendService.post(
        '/api/vehicles/',
        body: vehicle.toJson(),
      );
      return VehicleProfile.fromJson(response);
    } catch (e) {
      print('Error adding vehicle: $e');
      return null;
    }
  }

  /// Update an existing vehicle on the backend
  Future<VehicleProfile?> updateVehicle(VehicleProfile vehicle) async {
    try {
      final response = await BackendService.post(
        '/api/vehicles/${vehicle.id}',
        body: {
          'brand': vehicle.brand,
          'model': vehicle.model,
          'variant': vehicle.variant,
          'range_efficiency': vehicle.rangeEfficiency,
          'image_url': vehicle.imageUrl,
        },
      );
      return VehicleProfile.fromJson(response);
    } catch (e) {
      print('Error updating vehicle: $e');
      return null;
    }
  }

  /// Delete a vehicle from the backend
  Future<bool> deleteVehicle(String vehicleId) async {
    try {
      await BackendService.get('/api/vehicles/$vehicleId');
      return true;
    } catch (e) {
      print('Error deleting vehicle: $e');
      return false;
    }
  }
  Future<List<VehicleTemplate>> fetchVehicleTemplates() async {
    try {
      final response = await BackendService.get('/api/vehicles/templates');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => VehicleTemplate.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching vehicle templates: $e');
      return [];
    }
  }
}
