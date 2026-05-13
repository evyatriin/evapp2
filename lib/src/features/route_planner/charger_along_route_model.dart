import 'package:flutter/foundation.dart';

class ChargerAlongRoute {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;
  final String? provider;
  final List<String> connectorTypes;
  final double? powerKw;
  final double distanceFromOriginKm;
  final bool isOptimal;
  final String chargerType; // "optimal", "alternative", or "far"

  ChargerAlongRoute({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
    this.provider,
    this.connectorTypes = const [],
    this.powerKw,
    required this.distanceFromOriginKm,
    required this.isOptimal,
    required this.chargerType,
  });

  factory ChargerAlongRoute.fromJson(Map<String, dynamic> json) {
    try {
      return ChargerAlongRoute(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Unknown Charger',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        address: json['address'] as String?,
        provider: json['provider'] as String?,
        connectorTypes: List<String>.from(
          (json['connector_types'] as List?)?.map((x) => x.toString()) ?? [],
        ),
        powerKw: (json['power_kw'] as num?)?.toDouble(),
        distanceFromOriginKm: (json['distance_from_origin_km'] as num?)?.toDouble() ?? 0.0,
        isOptimal: json['is_optimal'] as bool? ?? false,
        chargerType: json['charger_type'] as String? ?? 'alternative',
      );
    } catch (e) {
      debugPrint('Error parsing ChargerAlongRoute: $e');
      return ChargerAlongRoute(
        id: '',
        name: 'Unknown',
        latitude: 0.0,
        longitude: 0.0,
        distanceFromOriginKm: 0.0,
        isOptimal: false,
        chargerType: 'alternative',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'address': address,
    'provider': provider,
    'connector_types': connectorTypes,
    'power_kw': powerKw,
    'distance_from_origin_km': distanceFromOriginKm,
    'is_optimal': isOptimal,
    'charger_type': chargerType,
  };

  @override
  String toString() => 'ChargerAlongRoute(id: $id, name: $name, distance: ${distanceFromOriginKm}km, type: $chargerType)';
}
