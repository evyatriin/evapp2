import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'station_model.dart';
import 'places_service.dart';

import 'remote_charger_service.dart';

part 'stations_repository.g.dart';

class StationsRepository {
  final PlacesService _placesService;
  final RemoteChargerService _remoteService;

  StationsRepository(this._placesService, this._remoteService);

  Future<List<StationModel>> getStationsNear(LatLng center, {double radiusKm = 10.0}) async {
    // Fetch from both sources in parallel
    final results = await Future.wait([
      _placesService.fetchChargingStations(center, radiusKm),
      _remoteService.fetchRemoteStations(center),
    ]);

    final placesStations = results[0];
    final remoteStations = results[1];

    // Merge and Deduplicate
    // We'll use a simple distance-based deduplication.
    // If a remote station is within 50 meters of a places station, we assume they are the same.
    // We'll prefer the Remote station as it might have more specific EV details (in a real scenario).
    
    final List<StationModel> mergedStations = [...remoteStations];
    const Distance distance = Distance();

    for (final placeStation in placesStations) {
      bool isDuplicate = false;
      for (final remoteStation in remoteStations) {
        if (distance.as(LengthUnit.Meter, placeStation.location, remoteStation.location) < 50) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        mergedStations.add(placeStation);
      }
    }

    return mergedStations;
  }
}

@riverpod
StationsRepository stationsRepository(Ref ref) {
  return StationsRepository(PlacesService(), RemoteChargerService());
}

@riverpod
class MapCenter extends _$MapCenter {
  @override
  LatLng build() => const LatLng(17.3850, 78.4867); // Default: Hyderabad

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
  print('DEBUG: Fetching stations for center: ${center.latitude}, ${center.longitude}, zoom: $zoom, radius: ${radiusKm}km');
  
  final allStations = await repository.getStationsNear(center, radiusKm: radiusKm);
  
  // Apply connector filter
  if (filters.isEmpty) {
    return allStations;
  }
  
  return allStations.where((station) {
    return station.connectors.any((c) => filters.contains(c));
  }).toList();
}

