import 'package:latlong2/latlong.dart';

class ElevationPoint {
  final double latitude;
  final double longitude;
  final double elevationM;
  final double distanceFromOriginKm;

  const ElevationPoint({
    required this.latitude,
    required this.longitude,
    required this.elevationM,
    required this.distanceFromOriginKm,
  });

  factory ElevationPoint.fromJson(Map<String, dynamic> json) {
    return ElevationPoint(
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      elevationM: json['elevation_m'].toDouble(),
      distanceFromOriginKm: json['distance_from_origin_km'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'elevation_m': elevationM,
      'distance_from_origin_km': distanceFromOriginKm,
    };
  }
}

class ElevationProfile {
  final double elevationGainM;
  final double elevationLossM;
  final double maxElevationM;
  final double minElevationM;
  final double averageGradientPct;
  final List<ElevationPoint> points;

  const ElevationProfile({
    required this.elevationGainM,
    required this.elevationLossM,
    required this.maxElevationM,
    required this.minElevationM,
    required this.averageGradientPct,
    required this.points,
  });

  factory ElevationProfile.fromJson(Map<String, dynamic> json) {
    return ElevationProfile(
      elevationGainM: json['elevation_gain_m'].toDouble(),
      elevationLossM: json['elevation_loss_m'].toDouble(),
      maxElevationM: json['max_elevation_m'].toDouble(),
      minElevationM: json['min_elevation_m'].toDouble(),
      averageGradientPct: json['average_gradient_pct'].toDouble(),
      points: (json['points'] as List)
          .map((point) => ElevationPoint.fromJson(point))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'elevation_gain_m': elevationGainM,
      'elevation_loss_m': elevationLossM,
      'max_elevation_m': maxElevationM,
      'min_elevation_m': minElevationM,
      'average_gradient_pct': averageGradientPct,
      'points': points.map((p) => p.toJson()).toList(),
    };
  }

  String get elevationSummary {
    if (elevationGainM == 0 && elevationLossM == 0) {
      return 'No elevation data';
    }
    return '↑ ${elevationGainM.toStringAsFixed(0)}m / ↓ ${elevationLossM.toStringAsFixed(0)}m';
  }
}

class RouteModel {
  final String id;
  final String name; // "Plan A", "Plan B", etc.
  final List<LatLng> polyline;
  final double totalDistanceKm;
  final double totalDurationMin;
  final List<RouteStop> stops;
  final double estimatedCost;
  final List<String> guidance;
  final ElevationProfile? elevationProfile;

  const RouteModel({
    required this.id,
    required this.name,
    required this.polyline,
    required this.totalDistanceKm,
    required this.totalDurationMin,
    required this.stops,
    required this.estimatedCost,
    this.guidance = const [],
    this.elevationProfile,
  });

  int get totalChargeDurationMin => stops
      .where((stop) => stop.type == StopType.charging)
      .fold<int>(0, (total, stop) => total + (stop.chargeDurationMin ?? 0));

  String get elevationSummary =>
      elevationProfile?.elevationSummary ?? 'No elevation data';

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      id: json['id'],
      name: json['name'],
      polyline: (json['polyline'] as List)
          .map((point) => LatLng(point['latitude'], point['longitude']))
          .toList(),
      totalDistanceKm: json['totalDistanceKm'].toDouble(),
      totalDurationMin: json['totalDurationMin'].toDouble(),
      stops: (json['stops'] as List)
          .map((stop) => RouteStop.fromJson(stop))
          .toList(),
      estimatedCost: json['estimatedCost'].toDouble(),
      guidance: (json['guidance'] as List<dynamic>?)
              ?.map((item) => item as String)
              .toList() ??
          const [],
      elevationProfile: json['elevationProfile'] != null
          ? ElevationProfile.fromJson(json['elevationProfile'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'polyline': polyline.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
      'totalDistanceKm': totalDistanceKm,
      'totalDurationMin': totalDurationMin,
      'stops': stops.map((s) => s.toJson()).toList(),
      'estimatedCost': estimatedCost,
      'guidance': guidance,
      'elevationProfile': elevationProfile?.toJson(),
    };
  }
}

enum StopType { origin, destination, charging, waypoint }

class RouteStop {
  final String name;
  final LatLng location;
  final StopType type;
  final DateTime arrivalTime;
  final int? arrivalSoc;
  final int? departureSoc;
  final double? cost;
  final int? chargeDurationMin;
  final int? targetSoc;
  final String? advice;
  final double? distanceFromOriginKm;
  final double? distanceFromPreviousStopKm;
  final double? distanceFromPreviousChargingStopKm;

  const RouteStop({
    required this.name,
    required this.location,
    required this.type,
    required this.arrivalTime,
    this.chargeDurationMin,
    this.targetSoc,
    this.arrivalSoc,
    this.departureSoc,
    this.cost,
    this.advice,
    this.distanceFromOriginKm,
    this.distanceFromPreviousStopKm,
    this.distanceFromPreviousChargingStopKm,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      name: json['name'],
      location: LatLng(json['location']['latitude'], json['location']['longitude']),
      type: StopType.values.firstWhere((e) => e.toString().split('.').last == json['type']),
      arrivalTime: DateTime.parse(json['arrivalTime']),
      chargeDurationMin: json['chargeDurationMin'],
      targetSoc: json['targetSoc'],
      arrivalSoc: json['arrivalSoc'],
      departureSoc: json['departureSoc'],
      cost: json['cost']?.toDouble(),
      advice: json['advice'] as String?,
      distanceFromOriginKm: (json['distanceFromOriginKm'] as num?)?.toDouble(),
      distanceFromPreviousStopKm: (json['distanceFromPreviousStopKm'] as num?)?.toDouble(),
      distanceFromPreviousChargingStopKm: (json['distanceFromPreviousChargingStopKm'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'location': {'latitude': location.latitude, 'longitude': location.longitude},
      'type': type.toString().split('.').last,
      'arrivalTime': arrivalTime.toIso8601String(),
      'chargeDurationMin': chargeDurationMin,
      'targetSoc': targetSoc,
      'arrivalSoc': arrivalSoc,
      'departureSoc': departureSoc,
      'cost': cost,
      'advice': advice,
      'distanceFromOriginKm': distanceFromOriginKm,
      'distanceFromPreviousStopKm': distanceFromPreviousStopKm,
      'distanceFromPreviousChargingStopKm': distanceFromPreviousChargingStopKm,
    };
  }
}
