import 'package:latlong2/latlong.dart';
import '../route_planner/route_model.dart';

class SavedRoute {
  final String id;
  final String userId;
  final String name;
  final LatLng startLocation;
  final String startAddress;
  final LatLng endLocation;
  final String endAddress;
  final String? vehicleId;
  final RouteModel routeData;
  final double distanceKm;
  final int durationMin;
  final int chargingStops;
  final bool isFavorite;
  final DateTime createdAt;
  final double? elevationGainM;
  final double? elevationLossM;

  const SavedRoute({
    required this.id,
    required this.userId,
    required this.name,
    required this.startLocation,
    required this.startAddress,
    required this.endLocation,
    required this.endAddress,
    this.vehicleId,
    required this.routeData,
    required this.distanceKm,
    required this.durationMin,
    required this.chargingStops,
    this.isFavorite = false,
    required this.createdAt,
    this.elevationGainM,
    this.elevationLossM,
  });

  SavedRoute copyWith({
    String? id,
    String? userId,
    String? name,
    LatLng? startLocation,
    String? startAddress,
    LatLng? endLocation,
    String? endAddress,
    String? vehicleId,
    RouteModel? routeData,
    double? distanceKm,
    int? durationMin,
    int? chargingStops,
    bool? isFavorite,
    DateTime? createdAt,
    double? elevationGainM,
    double? elevationLossM,
  }) {
    return SavedRoute(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      startLocation: startLocation ?? this.startLocation,
      startAddress: startAddress ?? this.startAddress,
      endLocation: endLocation ?? this.endLocation,
      endAddress: endAddress ?? this.endAddress,
      vehicleId: vehicleId ?? this.vehicleId,
      routeData: routeData ?? this.routeData,
      distanceKm: distanceKm ?? this.distanceKm,
      durationMin: durationMin ?? this.durationMin,
      chargingStops: chargingStops ?? this.chargingStops,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      elevationGainM: elevationGainM ?? this.elevationGainM,
      elevationLossM: elevationLossM ?? this.elevationLossM,
    );
  }

  // JSON serialization
  factory SavedRoute.fromJson(Map<String, dynamic> json) {
    final startLoc = json['start_location'] as Map<String, dynamic>;
    final endLoc = json['end_location'] as Map<String, dynamic>;

    return SavedRoute(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      startLocation: LatLng(
        (startLoc['lat'] as num).toDouble(),
        (startLoc['lng'] as num).toDouble(),
      ),
      startAddress: startLoc['address'] as String,
      endLocation: LatLng(
        (endLoc['lat'] as num).toDouble(),
        (endLoc['lng'] as num).toDouble(),
      ),
      endAddress: endLoc['address'] as String,
      vehicleId: json['vehicle_id'] as String?,
      routeData: RouteModel.fromJson(json['route_data']),
      distanceKm: (json['distance_km'] as num).toDouble(),
      durationMin: json['duration_min'] as int,
      chargingStops: json['charging_stops'] as int,
      isFavorite: json['is_favorite'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      elevationGainM: (json['elevation_gain_m'] as num?)?.toDouble(),
      elevationLossM: (json['elevation_loss_m'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'start_location': {
        'lat': startLocation.latitude,
        'lng': startLocation.longitude,
        'address': startAddress,
      },
      'end_location': {
        'lat': endLocation.latitude,
        'lng': endLocation.longitude,
        'address': endAddress,
      },
      'vehicle_id': vehicleId,
      'route_data': routeData.toJson(), // Assuming RouteModel has toJson
      'distance_km': distanceKm,
      'duration_min': durationMin,
      'charging_stops': chargingStops,
      'is_favorite': isFavorite,
      'created_at': createdAt.toIso8601String(),
      'elevation_gain_m': elevationGainM,
      'elevation_loss_m': elevationLossM,
    };
  }
}
