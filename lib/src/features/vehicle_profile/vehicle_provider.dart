import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../authentication/user_provider.dart';
import 'vehicle_model.dart';
import 'vehicle_template_model.dart';
import 'vehicle_service.dart';

final vehicleProvider = NotifierProvider<Vehicle, List<VehicleProfile>>(Vehicle.new);

class Vehicle extends Notifier<List<VehicleProfile>> {
  final _service = VehicleService();
  
  @override
  List<VehicleProfile> build() {
    ref.listen(userProvider.select((user) => user?.id), (previous, next) {
      if (next == null) {
        state = [];
        _service.clearCache(previous);
        return;
      }

      if (previous != next) {
        state = [];
        _loadWithCache(next);
      }
    });

    final userId = ref.watch(userProvider.select((user) => user?.id));
    if (userId != null) {
      _loadWithCache(userId);
    }

    return [];
  }

  Future<void> _loadWithCache(String userId) async {
    final cached = await _service.getCachedVehicles(userId);
    if (cached.isNotEmpty && ref.mounted) {
      state = cached;
    }

    if (!ref.mounted) return;

    final vehicles = await _service.fetchVehiclesWithCache(userId);
    if (ref.mounted && ref.read(userProvider)?.id == userId) {
      state = vehicles;
    }
  }

  /// Get the primary vehicle (or first vehicle if none is primary)
  VehicleProfile? get primaryVehicle {
    if (state.isEmpty) return null;
    final primary = state.where((v) => v.isPrimary).toList();
    return primary.isNotEmpty ? primary.first : state.first;
  }

  Future<VehicleProfile?> addVehicle(VehicleProfile vehicle) async {
    final addedVehicle = await _service.addVehicle(vehicle);
    if (addedVehicle != null) {
      final nextState = [
        for (final existing in state)
          existing.copyWith(
            isPrimary: addedVehicle.isPrimary ? false : existing.isPrimary,
          ),
        addedVehicle,
      ];
      state = nextState;
    }
    return addedVehicle;
  }

  Future<VehicleProfile?> updateVehicle(VehicleProfile updatedVehicle) async {
    final updated = await _service.updateVehicle(updatedVehicle);
    if (updated != null) {
      state = [
        for (final vehicle in state)
          if (vehicle.id == updated.id)
            updated
          else
            vehicle.copyWith(
              isPrimary: updated.isPrimary ? false : vehicle.isPrimary,
            ),
      ];
    }
    return updated;
  }

  Future<bool> removeVehicle(String id) async {
    final success = await _service.deleteVehicle(id);
    if (success) {
      final updated = state.where((v) => v.id != id).toList();
      if (updated.isNotEmpty && !updated.any((vehicle) => vehicle.isPrimary)) {
        updated[0] = updated[0].copyWith(isPrimary: true);
      }
      state = updated;
    }
    return success;
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
    final userId = ref.read(userProvider)?.id;
    if (userId == null) {
      state = [];
      return;
    }
    await _loadWithCache(userId);
  }
}

final vehicleTemplatesProvider = FutureProvider<List<VehicleTemplate>>((ref) async {
  final service = VehicleService();
  return service.fetchVehicleTemplates();
});
