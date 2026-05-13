import 'package:latlong2/latlong.dart';

class StationModel {
  final String id;
  final String name;
  final LatLng location;
  final String? provider;
  final String status; // working, busy, broken
  final DateTime? lastVerified;
  final String verifiedBy;
  final List<String> connectors;
  final List<String> amenities;
  final int? freshnessScore;
  final String? issueType;
  final double? rating;
  final int? userRatingCount;
  final String? address;
  final String? cost; // Placeholder
  final bool isPrivate;
  final String accessType;
  final String? availabilityStatus;
  final String? stationRecordId;
  final String? hostName;
  final String? hostPhone;
  final String? hostUpiId;
  final double? pricePerKwh;
  final double? pricePerSession;
  final String? availableFrom;
  final String? availableTo;
  final List<String> availableDays;
  final bool isAcceptingRequests;
  final String? parkingNotes;
  final String? houseRules;
  final String? phoneNumber;
  final List<String> chargerPhotos;
  final List<String> parkingPhotos;
  final String? propertyType;
  final String? visitorAccessType;
  final String? availableHours;
  final List<String> vehicleSizeSupport;
  final Map<String, bool> locationAccessChecks;
  final Map<String, bool> safetyChecks;
  final Map<String, bool> hostDeclarations;
  final String? declarationVersion;
  final String? declarationsCompletedAt;
  final List<String> moderationFlags;
  final Map<String, bool> verificationBadges;

  const StationModel({
    required this.id,
    required this.name,
    required this.location,
    this.provider,
    required this.status,
    this.lastVerified,
    required this.verifiedBy,
    required this.connectors,
    required this.amenities,
    this.freshnessScore,
    this.issueType,
    this.rating,
    this.userRatingCount,
    this.address,
    this.cost,
    this.isPrivate = false,
    this.accessType = 'Public',
    this.availabilityStatus,
    this.stationRecordId,
    this.hostName,
    this.hostPhone,
    this.hostUpiId,
    this.pricePerKwh,
    this.pricePerSession,
    this.availableFrom,
    this.availableTo,
    this.availableDays = const [],
    this.isAcceptingRequests = false,
    this.parkingNotes,
    this.houseRules,
    this.phoneNumber,
    this.chargerPhotos = const [],
    this.parkingPhotos = const [],
    this.propertyType,
    this.visitorAccessType,
    this.availableHours,
    this.vehicleSizeSupport = const [],
    this.locationAccessChecks = const {},
    this.safetyChecks = const {},
    this.hostDeclarations = const {},
    this.declarationVersion,
    this.declarationsCompletedAt,
    this.moderationFlags = const [],
    this.verificationBadges = const {},
  });

  factory StationModel.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    final lat =
        (location?['lat'] ?? location?['latitude'] ?? json['latitude'])
            as num?;
    final lng =
        (location?['lng'] ?? location?['longitude'] ?? json['longitude'])
            as num?;

    return StationModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Charging Station',
      location: LatLng((lat ?? 0).toDouble(), (lng ?? 0).toDouble()),
      provider: json['provider'] as String?,
      status: _normalizeStatus(json['status'] as String?),
      lastVerified: json['last_verified'] != null
          ? DateTime.tryParse(json['last_verified'])
          : null,
      verifiedBy: json['verified_by'] as String? ?? 'EVraahein',
      connectors: List<String>.from(
        json['connectors'] ?? json['connector_types'] ?? const [],
      ),
      amenities: List<String>.from(json['amenities'] ?? const []),
      freshnessScore: json['freshness_score'] as int?,
      issueType: json['issue_type'],
      rating: json['rating']?.toDouble(),
      userRatingCount: json['user_rating_count'],
      address: json['address'],
      cost: json['cost'],
      isPrivate: json['is_private'] ?? false,
      accessType: json['access_type'] ?? 'Public',
      availabilityStatus: json['availability_status'] as String?,
      stationRecordId: json['station_record_id']?.toString(),
      hostName: json['host_name'] as String?,
      hostPhone: json['host_phone'] as String?,
      hostUpiId: json['host_upi_id'] as String?,
      pricePerKwh: (json['price_per_kwh'] as num?)?.toDouble(),
      pricePerSession: (json['price_per_session'] as num?)?.toDouble(),
      availableFrom: json['available_from'] as String?,
      availableTo: json['available_to'] as String?,
      availableDays: List<String>.from(json['available_days'] ?? const []),
      isAcceptingRequests: json['is_accepting_requests'] == true,
      parkingNotes: json['parking_notes'] as String?,
      houseRules: json['house_rules'] as String?,
      phoneNumber: json['phone_number'] as String?,
      chargerPhotos: List<String>.from(json['charger_photos'] ?? const []),
      parkingPhotos: List<String>.from(json['parking_photos'] ?? const []),
      propertyType: json['property_type'] as String?,
      visitorAccessType: json['visitor_access_type'] as String?,
      availableHours: json['available_hours'] as String?,
      vehicleSizeSupport: List<String>.from(
        json['vehicle_size_support'] ?? const [],
      ),
      locationAccessChecks: Map<String, bool>.from(
        json['location_access_checks'] ?? const {},
      ),
      safetyChecks: Map<String, bool>.from(json['safety_checks'] ?? const {}),
      hostDeclarations: Map<String, bool>.from(
        json['host_declarations'] ?? const {},
      ),
      declarationVersion: json['declaration_version'] as String?,
      declarationsCompletedAt: json['declarations_completed_at'] as String?,
      moderationFlags: List<String>.from(json['moderation_flags'] ?? const []),
      verificationBadges: Map<String, bool>.from(
        json['verification_badges'] ?? const {},
      ),
    );
  }

  factory StationModel.fromPlacesJson(Map<String, dynamic> json) {
    final location = json['location'];
    final evOptions = json['evChargeOptions'];
    final connectors = <String>[];
    String status = 'working';
    String? availabilityStatus;

    if (evOptions != null && evOptions['connectorAggregation'] != null) {
      for (var agg in evOptions['connectorAggregation']) {
        if (agg['type'] != null) {
          connectors.add(_formatConnectorType(agg['type']));
        }
        final availability = agg['availability'] as String?;
        if (availability == 'AVAILABLE') {
          availabilityStatus = 'Available';
          status = 'working';
        } else if (availability == 'OCCUPIED' && availabilityStatus == null) {
          availabilityStatus = 'Busy';
          status = 'busy';
        } else if (availability == 'OUT_OF_SERVICE' &&
            availabilityStatus == null) {
          availabilityStatus = 'Out of service';
          status = 'broken';
        }
      }
    }

    return StationModel(
      id: json['id'],
      name: json['displayName']?['text'] ?? 'Unknown Station',
      location: LatLng(location['latitude'], location['longitude']),
      provider: null,
      status: status,
      lastVerified: null,
      verifiedBy: 'Google',
      connectors: connectors.isNotEmpty ? connectors : ['Unknown'],
      amenities: [], // Places API doesn't give amenities easily in this call
      freshnessScore: null,
      rating: json['rating']?.toDouble(),
      userRatingCount: json['userRatingCount'],
      address: json['formattedAddress'],
      cost: null,
      isPrivate: false,
      accessType: 'Public',
      availabilityStatus: availabilityStatus,
      stationRecordId: null,
      hostName: null,
      hostPhone: null,
      hostUpiId: null,
      pricePerKwh: null,
      pricePerSession: null,
      availableFrom: null,
      availableTo: null,
      availableDays: const [],
      isAcceptingRequests: false,
      parkingNotes: null,
      houseRules: null,
      phoneNumber: json['nationalPhoneNumber'] as String?,
      chargerPhotos: const [],
      parkingPhotos: const [],
      propertyType: null,
      visitorAccessType: null,
      availableHours: null,
      vehicleSizeSupport: const [],
      locationAccessChecks: const {},
      safetyChecks: const {},
      hostDeclarations: const {},
      declarationVersion: null,
      declarationsCompletedAt: null,
      moderationFlags: const [],
      verificationBadges: const {},
    );
  }

  /// Formats raw API connector types into user-friendly display names
  static String _formatConnectorType(String rawType) {
    // Remove common prefixes
    String formatted = rawType
        .replaceAll('EV_CONNECTOR_TYPE_', '')
        .replaceAll('EV_CONNECTOR_', '')
        .replaceAll('_', ' ');

    // Map known types to friendly names
    final typeMap = {
      'CCS COMBO 1': 'CCS1',
      'CCS COMBO 2': 'CCS2',
      'CHADEMO': 'CHAdeMO',
      'J1772': 'Type 1 (J1772)',
      'TYPE 2': 'Type 2',
      'TYPE 1': 'Type 1',
      'TESLA': 'Tesla',
      'GB T': 'GB/T',
      'GBT': 'GB/T',
      'UNSPECIFIED': 'Standard',
      'OTHER': 'Other',
    };

    // Check if we have a mapping
    final upperFormatted = formatted.toUpperCase().trim();
    if (typeMap.containsKey(upperFormatted)) {
      return typeMap[upperFormatted]!;
    }

    // Title case the result if no mapping found
    return formatted.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ').trim();
  }

  static String _normalizeStatus(String? rawStatus) {
    final normalized = (rawStatus ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return 'working';
    if (normalized == 'working' ||
        normalized == 'operational' ||
        normalized == 'available') {
      return 'working';
    }
    if (normalized == 'busy' || normalized == 'occupied') {
      return 'busy';
    }
    if (normalized == 'broken' ||
        normalized == 'out_of_service' ||
        normalized == 'out of service') {
      return 'broken';
    }
    return normalized;
  }
}
