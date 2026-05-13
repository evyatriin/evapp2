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

  const ChargersMarkerLayer({
    Key? key,
    required this.chargers,
    required this.onChargerTap,
    this.showOptimalOnly = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Filter chargers if showing optimal only
    final displayChargers = showOptimalOnly
        ? chargers.where((c) => c.isOptimal).toList()
        : chargers;

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
