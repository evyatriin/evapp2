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

  Future<List<StationModel>> getStationsNear(LatLng center) async {
    // Fetch from both sources in parallel
    final results = await Future.wait([
      _placesService.fetchChargingStations(center, 5.0),
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

@riverpod
Future<List<StationModel>> stations(Ref ref) async {
  final repository = ref.watch(stationsRepositoryProvider);
  final center = ref.watch(mapCenterProvider);
  final filters = ref.watch(connectorFilterProvider);
  print('DEBUG: Fetching stations for center: ${center.latitude}, ${center.longitude}');
  
  final allStations = await repository.getStationsNear(center);
  
  // Apply connector filter
  if (filters.isEmpty) {
    return allStations;
  }
  
  return allStations.where((station) {
    return station.connectors.any((c) => filters.contains(c));
  }).toList();
}

