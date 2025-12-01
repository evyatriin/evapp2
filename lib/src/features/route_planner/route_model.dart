import 'package:latlong2/latlong.dart';

class RouteModel {
  final String id;
  final String name; // "Plan A", "Plan B", etc.
  final List<LatLng> polyline;
  final double totalDistanceKm;
  final double totalDurationMin;
  final List<RouteStop> stops;
  final double estimatedCost;

  const RouteModel({
    required this.id,
    required this.name,
    required this.polyline,
    required this.totalDistanceKm,
    required this.totalDurationMin,
    required this.stops,
    required this.estimatedCost,
  });

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
    };
  }
}
