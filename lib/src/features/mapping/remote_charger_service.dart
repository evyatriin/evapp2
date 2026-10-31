import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/backend_service.dart';
import '../../core/offline_cache.dart';
import '../authentication/auth_service.dart';
import 'station_model.dart';

class RemoteChargerService {
  /// Cache key for the nearby-chargers result at [center]/[radiusKm].
  /// Coordinates are rounded to 2 d.p. (~1.1 km) so nearby requests reuse it.
  String _cacheKey(LatLng? center, double radiusKm) {
    if (center == null) return 'nearby_chargers_all';
    return 'nearby_chargers'
        '_${center.latitude.toStringAsFixed(2)}'
        '_${center.longitude.toStringAsFixed(2)}'
        '_${radiusKm.toStringAsFixed(0)}';
  }

  Future<List<StationModel>> fetchRemoteStations(
    LatLng? center, {
    double radiusKm = 10.0,
  }) async {
    // Prefer AuthService.currentToken (set at login, survives session restore)
    // then fall back to Supabase client session as secondary option.
    final token = AuthService.currentToken
        ?? Supabase.instance.client.auth.currentSession?.accessToken;
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

    final cacheKey = _cacheKey(center, radiusKm);
    try {
      final response = await BackendService.get(
        '/api/chargers/aggregate',
        queryParams: queryParams,
        headers: {'Authorization': 'Bearer $token'},
      );
      final List<dynamic> data = response as List<dynamic>;
      // Persist raw JSON so a slow/cold backend still shows last-known pins.
      unawaited(OfflineCache.set(cacheKey, data));
      return data.map((json) => StationModel.fromJson(json)).toList();
    } catch (e) {
      // Network/backend error (e.g. cold start timeout): fall back to the
      // last successful result for this area so the map is never empty.
      final cached = await OfflineCache.get(cacheKey);
      final cachedData = cached?.data;
      if (cachedData is List && cachedData.isNotEmpty) {
        debugPrint(
          '[RemoteChargerService] fetch failed ($e) — serving '
          '${cachedData.length} cached chargers (${cached!.freshnessLabel})',
        );
        return cachedData
            .map((json) => StationModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }
      rethrow;
    }
  }
}
