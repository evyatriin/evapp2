import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'vehicle_model.dart';
import 'vehicle_template_model.dart';
import '../../core/backend_service.dart';
import '../authentication/auth_service.dart';

class VehicleService {
  final _authService = AuthService();
  
  static const String _vehiclesCacheKey = 'cached_vehicles';
  static const String _vehiclesHashKey = 'cached_vehicles_hash';

  /// Get current user ID from auth service
  String? getCurrentUserId() {
    return _authService.currentUserId;
  }

  /// Get cached vehicles from local storage
  Future<List<VehicleProfile>> getCachedVehicles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_vehiclesCacheKey);
      if (cachedJson != null) {
        final List<dynamic> data = json.decode(cachedJson);
        return data.map((j) => VehicleProfile.fromJson(j)).toList();
      }
    } catch (e) {
      print('Error reading cache: $e');
    }
    return [];
  }

  /// Save vehicles to local cache
  Future<void> _cacheVehicles(List<VehicleProfile> vehicles, String hash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(vehicles.map((v) => v.toJson()).toList());
      await prefs.setString(_vehiclesCacheKey, jsonData);
      await prefs.setString(_vehiclesHashKey, hash);
    } catch (e) {
      print('Error caching vehicles: $e');
    }
  }

  /// Get cached hash
  Future<String?> _getCachedHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_vehiclesHashKey);
  }

  /// Fetch hash from server for cache validation
  Future<String?> fetchVehiclesHash(String userId) async {
    try {
      final response = await BackendService.get('/api/vehicles/hash/$userId');
      return response?['hash'] as String?;
    } catch (e) {
      print('Error fetching hash: $e');
      return null;
    }
  }

  /// Smart fetch: returns cached if valid, fetches fresh if stale
  Future<List<VehicleProfile>> fetchVehiclesWithCache(String userId) async {
    // Get cached data immediately
    final cachedVehicles = await getCachedVehicles();
    final cachedHash = await _getCachedHash();
    
    // Fetch server hash to check if cache is valid
    final serverHash = await fetchVehiclesHash(userId);
    
    // If hash matches, return cached data
    if (serverHash != null && serverHash == cachedHash && cachedVehicles.isNotEmpty) {
      print('[CACHE] Using cached vehicles (hash match)');
      return cachedVehicles;
    }
    
    // Cache is stale or empty, fetch fresh data
    print('[CACHE] Fetching fresh vehicles');
    final freshVehicles = await fetchVehicles(userId);
    
    // Cache the fresh data with new hash
    if (serverHash != null) {
      await _cacheVehicles(freshVehicles, serverHash);
    }
    
    return freshVehicles;
  }

  /// Clear vehicle cache (call when user logs out)
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vehiclesCacheKey);
    await prefs.remove(_vehiclesHashKey);
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
      await BackendService.delete('/api/vehicles/$vehicleId');
      return true;
    } catch (e) {
      print('Error deleting vehicle: $e');
      return false;
    }
  }

  /// Set a vehicle as the primary vehicle
  Future<bool> setPrimaryVehicle(String vehicleId) async {
    try {
      await BackendService.put('/api/vehicles/$vehicleId/primary', body: {});
      return true;
    } catch (e) {
      print('Error setting primary vehicle: $e');
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
