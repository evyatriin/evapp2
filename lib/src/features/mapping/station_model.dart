import 'package:latlong2/latlong.dart';

class StationModel {
  final String id;
  final String name;
  final LatLng location;
  final String provider;
  final String status; // working, busy, broken
  final DateTime lastVerified;
  final String verifiedBy;
  final List<String> connectors;
  final List<String> amenities;
  final int freshnessScore;
  final String? issueType;
  final double? rating;
  final int? userRatingCount;
  final String? address;
  final String? cost; // Placeholder
  final bool isPrivate;
  final String accessType;
  final String availabilityStatus;

  const StationModel({
    required this.id,
    required this.name,
    required this.location,
    required this.provider,
    required this.status,
    required this.lastVerified,
    required this.verifiedBy,
    required this.connectors,
    required this.amenities,
    required this.freshnessScore,
    this.issueType,
    this.rating,
    this.userRatingCount,
    this.address,
    this.cost,
    this.isPrivate = false,
    this.accessType = 'Public',
    this.availabilityStatus = 'Unknown',
  });

  factory StationModel.fromJson(Map<String, dynamic> json) {
    return StationModel(
      id: json['id'],
      name: json['name'],
      location: LatLng(json['location']['lat'], json['location']['lng']),
      provider: json['provider'],
      status: json['status'],
      lastVerified: DateTime.parse(json['last_verified']),
      verifiedBy: json['verified_by'],
      connectors: List<String>.from(json['connectors']),
      amenities: List<String>.from(json['amenities']),
      freshnessScore: json['freshness_score'],
      issueType: json['issue_type'],
      rating: json['rating']?.toDouble(),
      userRatingCount: json['user_rating_count'],
      address: json['address'],
      cost: json['cost'],
      isPrivate: json['is_private'] ?? false,
      accessType: json['access_type'] ?? 'Public',
      availabilityStatus: json['availability_status'] ?? 'Unknown',
    );
  }

  factory StationModel.fromPlacesJson(Map<String, dynamic> json) {
    final location = json['location'];
    final evOptions = json['evChargeOptions'];
    final connectors = <String>[];
    String status = 'working'; // Default

    if (evOptions != null && evOptions['connectorAggregation'] != null) {
      for (var agg in evOptions['connectorAggregation']) {
        if (agg['type'] != null) {
          connectors.add(agg['type']);
        }
        // Simple logic: if any connector is available, station is working
        if (agg['availability'] == 'OUT_OF_SERVICE') {
          status = 'broken';
        }
      }
    }

    return StationModel(
      id: json['id'],
      name: json['displayName']?['text'] ?? 'Unknown Station',
      location: LatLng(location['latitude'], location['longitude']),
      provider: 'Google Places', // Placeholder
      status: status,
      lastVerified: DateTime.now(), // Placeholder
      verifiedBy: 'Google',
      connectors: connectors.isNotEmpty ? connectors : ['Unknown'],
      amenities: [], // Places API doesn't give amenities easily in this call
      freshnessScore: 100,
      rating: json['rating']?.toDouble(),
      userRatingCount: json['userRatingCount'],
      address: json['formattedAddress'],
      cost: '₹15-25 / kWh', // Placeholder
      isPrivate: false,
      accessType: 'Public',
      availabilityStatus: 'Unknown',
    );
  }
}
