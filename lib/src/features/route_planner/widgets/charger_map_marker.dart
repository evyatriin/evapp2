import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../charger_along_route_model.dart';

class ChargerMapMarker extends StatelessWidget {
  final ChargerAlongRoute charger;
  final VoidCallback onTap;
  final bool showLabel;

  const ChargerMapMarker({
    Key? key,
    required this.charger,
    required this.onTap,
    this.showLabel = true,
  }) : super(key: key);

  /// Get color based on charger type
  Color get markerColor {
    switch (charger.chargerType) {
      case 'optimal':
        return Colors.green; // On recommended route
      case 'alternative':
        return Colors.blue; // Nearby but not on route
      case 'far':
        return Colors.grey; // Far from route
      default:
        return Colors.blue;
    }
  }

  /// Get background color for marker circle
  Color get backgroundColor {
    return markerColor.withOpacity(0.2);
  }

  /// Get marker icon
  IconData get markerIcon {
    return Icons.ev_station;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor,
              border: Border.all(
                color: markerColor,
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                markerIcon,
                color: markerColor,
                size: 20,
              ),
            ),
          ),
          // Distance label (positioned above marker)
          if (showLabel)
            Positioned(
              bottom: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: markerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${charger.distanceFromOriginKm.toStringAsFixed(1)}km',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Marker layer for chargers along route
class ChargersMarkerLayer extends StatelessWidget {
  final List<ChargerAlongRoute> chargers;
  final Function(ChargerAlongRoute) onChargerTap;
  final bool showOptimalOnly;
  final int targetMarkerCount;
  final double minGeoSeparationKm;

  const ChargersMarkerLayer({
    Key? key,
    required this.chargers,
    required this.onChargerTap,
    this.showOptimalOnly = false,
    this.targetMarkerCount = 10,
    this.minGeoSeparationKm = 25.0,
  }) : super(key: key);

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }

  /// Pick ~targetMarkerCount chargers evenly distributed along the route.
  ///
  /// Algorithm: place N anchor points evenly along the route by along-route
  /// distance, then for each anchor pick the closest unused charger. Skip
  /// anchors with no nearby candidate (avoids forcing far-off chargers).
  /// Enforce a minimum geographic (haversine) separation so chargers that
  /// share a city don't render on top of each other.
  List<ChargerAlongRoute> _spaceAlongRoute(List<ChargerAlongRoute> input) {
    if (input.length <= 2) return input;

    final sorted = [...input]
      ..sort((a, b) => a.distanceFromOriginKm.compareTo(b.distanceFromOriginKm));

    final routeLen = sorted.last.distanceFromOriginKm;
    if (routeLen < 50) return sorted; // Short route: show everything

    final n = math.max(4, math.min(targetMarkerCount, (routeLen / 60).round()));
    final maxDelta = routeLen / n; // Anchor must have a charger within half-segment

    final selected = <ChargerAlongRoute>[];
    final used = <String>{};

    bool conflictsGeo(ChargerAlongRoute c) {
      for (final s in selected) {
        if (_haversineKm(c.latitude, c.longitude, s.latitude, s.longitude) <
            minGeoSeparationKm) {
          return true;
        }
      }
      return false;
    }

    for (int i = 0; i < n; i++) {
      final target = (routeLen / (n - 1)) * i;
      ChargerAlongRoute? best;
      double bestScore = double.infinity;
      for (final c in sorted) {
        if (used.contains(c.id)) continue;
        final delta = (c.distanceFromOriginKm - target).abs();
        if (delta > maxDelta) continue;
        if (conflictsGeo(c)) continue;
        // Prefer on-route (optimal) and higher power: subtract a bonus from delta
        final bonus = (c.isOptimal ? 8.0 : 0.0) + (c.powerKw ?? 0) * 0.05;
        final score = delta - bonus;
        if (score < bestScore) {
          bestScore = score;
          best = c;
        }
      }
      if (best != null) {
        selected.add(best);
        used.add(best.id);
      }
    }

    selected.sort((a, b) => a.distanceFromOriginKm.compareTo(b.distanceFromOriginKm));
    return selected;
  }

  /// Returns the filtered+spaced charger list for reuse by connector layer.
  List<ChargerAlongRoute> buildDisplayList() {
    final filtered = showOptimalOnly
        ? chargers.where((c) => c.isOptimal).toList()
        : chargers;
    return _spaceAlongRoute(filtered);
  }

  @override
  Widget build(BuildContext context) {
    final displayChargers = buildDisplayList();
    return MarkerLayer(
      markers: displayChargers
          .map(
            (charger) => Marker(
              point: LatLng(charger.latitude, charger.longitude),
              width: 50,
              height: 50,
              child: ChargerMapMarker(
                charger: charger,
                onTap: () => onChargerTap(charger),
                showLabel: true,
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Draws dashed "detour" connector lines from off-route chargers to their
/// nearest point on the route. Must be added to FlutterMap.children BEFORE
/// [ChargersMarkerLayer] so markers render on top of lines.
class ChargersConnectorLayer extends StatelessWidget {
  final List<ChargerAlongRoute> chargers;
  final bool showOptimalOnly;

  const ChargersConnectorLayer({
    Key? key,
    required this.chargers,
    this.showOptimalOnly = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];
    final source = showOptimalOnly
        ? chargers.where((c) => c.isOptimal)
        : chargers;

    for (final c in source) {
      if (!c.isOptimal &&
          c.nearestRouteLat != null &&
          c.nearestRouteLng != null &&
          c.distToRouteKm > 0.3) {
        polylines.add(
          Polyline(
            points: [
              LatLng(c.latitude, c.longitude),
              LatLng(c.nearestRouteLat!, c.nearestRouteLng!),
            ],
            color: Colors.blue.withValues(alpha: 0.55),
            strokeWidth: 1.5,
            pattern: StrokePattern.dashed(segments: const [6, 5]),
          ),
        );
      }
    }

    return PolylineLayer(polylines: polylines);
  }
}
