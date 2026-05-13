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

// Speed filter: 'AC' | 'DC Fast'
@riverpod
class SpeedFilter extends _$SpeedFilter {
  @override
  Set<String> build() => {};

  void toggle(String speed) {
    if (state.contains(speed)) {
      state = {...state}..remove(speed);
    } else {
      state = {...state, speed};
    }
  }

  void clear() {
    state = {};
  }
}

// Price filter: 'Free' | 'Paid' | 'Community'
@riverpod
class PriceFilter extends _$PriceFilter {
  @override
  Set<String> build() => {};

  void toggle(String price) {
    if (state.contains(price)) {
      state = {...state}..remove(price);
    } else {
      state = {...state, price};
    }
  }

  void clear() {
    state = {};
  }
}

// Availability filter: show only 'working' stations
@riverpod
class AvailableNowFilter extends _$AvailableNowFilter {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void clear() => state = false;
}

// Access-type filter: 'Public' | 'Community Hosted'
@riverpod
class AccessFilter extends _$AccessFilter {
  @override
  Set<String> build() => {};

  void toggle(String access) {
    if (state.contains(access)) {
      state = {...state}..remove(access);
    } else {
      state = {...state, access};
    }
  }

  void clear() {
    state = {};
  }

}

/// DC connector type names (used for speed-filter approximation)
const _kDcConnectors = {'CCS2', 'CCS1', 'CHAdeMO', 'GB/T', 'Tesla'};

/// Returns how many filter groups have at least one active option.
int totalActiveFilters({
  required Set<String> connectors,
  required Set<String> speed,
  required Set<String> price,
  required bool availableNow,
  required Set<String> access,
}) {
  int count = 0;
  if (connectors.isNotEmpty) count++;
  if (speed.isNotEmpty) count++;
  if (price.isNotEmpty) count++;
  if (availableNow) count++;
  if (access.isNotEmpty) count++;
  return count;
}

/// Calculate search radius in km from zoom level.
/// Uses 70 000 / 2^zoom so zoom 12 yields ~17 km — covering the full visible
/// area on a typical phone — while the 50 km cap avoids slow/timed-out
/// backend queries at extreme zoom-out.
double _calculateRadiusFromZoom(double zoom) {
  final calculatedRadius = 70000 / (1 << zoom.round());
  return calculatedRadius.clamp(12.0, 50.0);
}

double _round4(double v) => (v * 10000).round() / 10000;

@riverpod
Future<List<StationModel>> stations(Ref ref) async {
  final repository = ref.watch(stationsRepositoryProvider);
  final rawCenter = ref.watch(mapCenterProvider);
  final zoom = ref.watch(mapZoomProvider);

  // Filter state
  final connectors = ref.watch(connectorFilterProvider);
  final speed = ref.watch(speedFilterProvider);
  final price = ref.watch(priceFilterProvider);
  final availableNow = ref.watch(availableNowFilterProvider);
  final access = ref.watch(accessFilterProvider);

  // Round to 4 decimal places (~11m) so near-identical positions share one request
  final center = LatLng(_round4(rawCenter.latitude), _round4(rawCenter.longitude));

  final radiusKm = _calculateRadiusFromZoom(zoom);
  debugPrint(
    'DEBUG: Fetching stations for center: ${center.latitude}, ${center.longitude}, zoom: $zoom, radius: ${radiusKm}km',
  );

  var result = await repository.getStationsNear(center, radiusKm: radiusKm);

  // --- Connector type filter ---
  if (connectors.isNotEmpty) {
    result = result.where((s) => s.connectors.any((c) => connectors.contains(c))).toList();
  }

  // --- Speed filter (approximated from connector types) ---
  if (speed.isNotEmpty) {
    result = result.where((s) {
      if (speed.contains('DC Fast') && s.connectors.any((c) => _kDcConnectors.contains(c))) return true;
      if (speed.contains('AC') && s.connectors.any((c) => !_kDcConnectors.contains(c))) return true;
      return false;
    }).toList();
  }

  // --- Price filter ---
  if (price.isNotEmpty) {
    result = result.where((s) {
      final kwh = s.pricePerKwh;
      if (price.contains('Free') && (kwh == null || kwh == 0) && !s.isAcceptingRequests) return true;
      if (price.contains('Paid') && kwh != null && kwh > 0) return true;
      if (price.contains('Community') && s.isAcceptingRequests) return true;
      return false;
    }).toList();
  }

  // --- Availability filter ---
  if (availableNow) {
    result = result.where((s) => s.status == 'working').toList();
  }

  // --- Access type filter ---
  if (access.isNotEmpty) {
    result = result.where((s) {
      if (access.contains('Public') && !s.isPrivate && !s.isAcceptingRequests) return true;
      if (access.contains('Community Hosted') && s.isAcceptingRequests) return true;
      return false;
    }).toList();
  }

  return result;
}
