import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/backend_service.dart';
import '../../core/offline_cache.dart';
import 'charger_along_route_model.dart';

class ChargerRouteService {
  /// Fetch chargers along a route.
  ///
  /// On success: stores result in [OfflineCache] for offline use.
  /// On failure (network error / offline): attempts to return cached result
  /// tagged with [fromCache] = true, so the UI can show a freshness label.
  Future<ChargerRouteResult> getChargersAlongRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? polyline,
    double radiusKm = 20.0,
  }) async {
    final cacheKey = OfflineCache.chargersRouteKey(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );

    // Try live fetch first (safePost checks connectivity before hitting network)
    final result = await BackendService.safePost(
      '/api/chargers/along-route',
      body: {
        'origin_lat': origin.latitude,
        'origin_lng': origin.longitude,
        'destination_lat': destination.latitude,
        'destination_lng': destination.longitude,
        'radius_km': radiusKm,
        if (polyline != null && polyline.isNotEmpty)
          'polyline': polyline
              .map((p) => {'latitude': p.latitude, 'longitude': p.longitude})
              .toList(),
      },
    );

    return result.when(
      success: (response) {
        if (response is! List) {
          debugPrint('[ChargerRouteService] Unexpected response type: ${response.runtimeType}');
          return _loadFromCache(cacheKey);
        }

        final chargers = _parseChargers(response);
        debugPrint('[ChargerRouteService] Fetched ${chargers.length} chargers (live)');

        // Persist for offline use (fire and forget)
        OfflineCache.set(cacheKey, response);

        return ChargerRouteResult(chargers: chargers, fromCache: false);
      },
      failure: (error) {
        debugPrint('[ChargerRouteService] Fetch failed (${error.kind.name}): ${error.message}');
        return _loadFromCache(cacheKey);
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<ChargerRouteResult> _loadFromCache(String cacheKey) async {
    final entry = await OfflineCache.get(cacheKey);
    if (entry == null || entry.data is! List) {
      return const ChargerRouteResult(chargers: [], fromCache: false);
    }
    final chargers = _parseChargers(entry.data as List);
    debugPrint('[ChargerRouteService] Loaded ${chargers.length} chargers from cache (${entry.freshnessLabel})');
    return ChargerRouteResult(
      chargers: chargers,
      fromCache: true,
      cacheLabel: entry.freshnessLabel,
      isStale: entry.isStale,
    );
  }

  List<ChargerAlongRoute> _parseChargers(List<dynamic> raw) {
    try {
      return raw
          .cast<Map<String, dynamic>>()
          .map(ChargerAlongRoute.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[ChargerRouteService] Parse error: $e');
      return [];
    }
  }

  /// Get only optimal chargers (those on the recommended route).
  Future<ChargerRouteResult> getOptimalChargersAlongRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? polyline,
  }) async {
    final result = await getChargersAlongRoute(
      origin: origin,
      destination: destination,
      polyline: polyline,
    );
    return result.copyWith(
      chargers: result.chargers.where((c) => c.isOptimal).toList(),
    );
  }
}

// ─── Result wrapper ───────────────────────────────────────────────────────────

class ChargerRouteResult {
  final List<ChargerAlongRoute> chargers;

  /// True when data came from cache (network was unavailable or errored).
  final bool fromCache;

  /// Human-readable label describing how old the cached data is,
  /// e.g. "Updated 12 min ago". Null when [fromCache] is false.
  final String? cacheLabel;

  /// True when the cache entry is older than 24 hours.
  final bool isStale;

  const ChargerRouteResult({
    required this.chargers,
    required this.fromCache,
    this.cacheLabel,
    this.isStale = false,
  });

  ChargerRouteResult copyWith({
    List<ChargerAlongRoute>? chargers,
    bool? fromCache,
    String? cacheLabel,
    bool? isStale,
  }) =>
      ChargerRouteResult(
        chargers: chargers ?? this.chargers,
        fromCache: fromCache ?? this.fromCache,
        cacheLabel: cacheLabel ?? this.cacheLabel,
        isStale: isStale ?? this.isStale,
      );
}
