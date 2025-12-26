import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'vehicle_model.dart';
import 'vehicle_template_model.dart';
import 'vehicle_service.dart';

final vehicleProvider = NotifierProvider<Vehicle, List<VehicleProfile>>(Vehicle.new);

class Vehicle extends Notifier<List<VehicleProfile>> {
  final _service = VehicleService();
  
  @override
  List<VehicleProfile> build() {
    // Load vehicles from backend
    _loadVehicles();
    
    // Return empty list initially, will be populated by _loadVehicles
    return [];
  }

  Future<void> _loadVehicles() async {
    // Get actual user ID from auth service
    final userId = _service.getCurrentUserId();
    
    if (userId != null) {
      final vehicles = await _service.fetchVehicles(userId);
      state = vehicles;
    }
  }

  /// Get the primary vehicle (or first vehicle if none is primary)
  VehicleProfile? get primaryVehicle {
    if (state.isEmpty) return null;
    final primary = state.where((v) => v.isPrimary).toList();
    return primary.isNotEmpty ? primary.first : state.first;
  }

  Future<void> addVehicle(VehicleProfile vehicle) async {
    final addedVehicle = await _service.addVehicle(vehicle);
    if (addedVehicle != null) {
      state = [...state, addedVehicle];
    }
  }

  Future<void> updateVehicle(VehicleProfile updatedVehicle) async {
    final updated = await _service.updateVehicle(updatedVehicle);
    if (updated != null) {
      state = [
        for (final vehicle in state)
          if (vehicle.id == updated.id) updated else vehicle,
      ];
    }
  }

  Future<void> removeVehicle(String id) async {
    final success = await _service.deleteVehicle(id);
    if (success) {
      state = state.where((v) => v.id != id).toList();
    }
  }

  /// Set a vehicle as the primary vehicle
  Future<void> setPrimaryVehicle(String vehicleId) async {
    final success = await _service.setPrimaryVehicle(vehicleId);
    if (success) {
      state = [
        for (final vehicle in state)
          vehicle.copyWith(isPrimary: vehicle.id == vehicleId),
      ];
    }
  }

  Future<void> refresh() async {
    await _loadVehicles();
  }
}

final vehicleTemplatesProvider = FutureProvider<List<VehicleTemplate>>((ref) async {
  final service = VehicleService();
  return service.fetchVehicleTemplates();
});
