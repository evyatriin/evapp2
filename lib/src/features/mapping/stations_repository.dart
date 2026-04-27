import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'remote_charger_service.dart';
import 'station_model.dart';

part 'stations_repository.g.dart';

const LatLng kFallbackMapCenter = LatLng(20.5937, 78.9629);

class StationsRepository {
  final RemoteChargerService _remoteService;

  StationsRepository(this._remoteService);

  Future<List<StationModel>> getStationsNear(
    LatLng center, {
    double radiusKm = 10.0,
  }) async {
    return _remoteService.fetchRemoteStations(center, radiusKm: radiusKm);
  }
}

@riverpod
StationsRepository stationsRepository(Ref ref) {
  return StationsRepository(RemoteChargerService());
}

@riverpod
class MapCenter extends _$MapCenter {
  @override
  LatLng build() => kFallbackMapCenter;

  void update(LatLng newCenter) {
    state = newCenter;
  }
}

// Map zoom level provider
@riverpod
class MapZoom extends _$MapZoom {
  @override
  double build() => 12.0; // Default zoom level

  void update(double newZoom) {
    state = newZoom;
  }
}

// Connector filter provider
@riverpod
class ConnectorFilter extends _$ConnectorFilter {
  @override
  Set<String> build() => {}; // Empty = show all

  void toggle(String connector) {
    if (state.contains(connector)) {
      state = {...state}..remove(connector);
    } else {
      state = {...state, connector};
    }
  }

  void clear() {
    state = {};
  }
}

/// Calculate search radius in km from zoom level
/// Google Maps zoom levels: 1 (world) to 20 (buildings)
/// Approx: Zoom 12 = ~5km visible, Zoom 10 = ~20km, Zoom 8 = ~80km
double _calculateRadiusFromZoom(double zoom) {
  // Formula: radius = 40000 / (2^zoom) km (rough approximation)
  // We'll cap at a reasonable max to avoid too many API calls
  final calculatedRadius = 40000 / (1 << zoom.round());
  // Clamp between 5km and 50km
  return calculatedRadius.clamp(5.0, 50.0);
}

@riverpod
Future<List<StationModel>> stations(Ref ref) async {
  final repository = ref.watch(stationsRepositoryProvider);
  final center = ref.watch(mapCenterProvider);
  final zoom = ref.watch(mapZoomProvider);
  final filters = ref.watch(connectorFilterProvider);

  final radiusKm = _calculateRadiusFromZoom(zoom);
  debugPrint(
    'DEBUG: Fetching stations for center: ${center.latitude}, ${center.longitude}, zoom: $zoom, radius: ${radiusKm}km',
  );

  final allStations = await repository.getStationsNear(
    center,
    radiusKm: radiusKm,
  );

  // Apply connector filter
  if (filters.isEmpty) {
    return allStations;
  }

  return allStations.where((station) {
    return station.connectors.any((c) => filters.contains(c));
  }).toList();
}
