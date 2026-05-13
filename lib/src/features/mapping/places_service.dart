import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../core/backend_service.dart';
import 'station_model.dart';

class PlacesService {
  Future<List<StationModel>> fetchChargingStations(
    LatLng center,
    double radiusKm,
  ) async {
    try {
      final response = await BackendService.post(
        '/api/places/nearby',
        body: {
          'center': {
            'latitude': center.latitude,
            'longitude': center.longitude,
          },
          'radius_km': radiusKm,
        },
      );

      final data = response as Map<String, dynamic>;
      final List<dynamic> places = data['places'] ?? [];
      return places.map((json) => StationModel.fromPlacesJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching places from backend: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getAutocompleteSuggestions(
    String query,
  ) async {
    if (query.length < 3) return [];

    try {
      final response = await BackendService.get(
        '/api/places/autocomplete',
        queryParams: {'input': query},
      );
      final data = response as Map<String, dynamic>;
      final predictions = data['predictions'] as List<dynamic>;

      return predictions
          .map(
            (p) => {
              'description': p['description'] as String,
              'place_id': p['place_id'] as String,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Error fetching autocomplete: $e');
      return [];
    }
  }

  Future<LatLng?> getPlaceDetails(String placeId) async {
    try {
      final response = await BackendService.get(
        '/api/places/details',
        queryParams: {'place_id': placeId},
      );
      final data = response as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>;
      final geometry = result['geometry'] as Map<String, dynamic>;
      final location = geometry['location'] as Map<String, dynamic>;

      return LatLng(location['lat'] as double, location['lng'] as double);
    } catch (e) {
      debugPrint('Error fetching place details: $e');
      return null;
    }
  }

  Future<List<NearbyFoodPlace>> fetchNearbyFoodPlaces(
    LatLng center, {
    double radiusKm = 10,
    int maxResults = 5,
  }) async {
    try {
      final response = await BackendService.post(
        '/api/places/food-nearby',
        body: {
          'center': {
            'latitude': center.latitude,
            'longitude': center.longitude,
          },
          'radius_km': radiusKm,
          'max_results': maxResults,
        },
      );

      final data = response as Map<String, dynamic>;
      final List<dynamic> places = data['places'] ?? [];
      return places
          .map((json) => NearbyFoodPlace.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching nearby food places: $e');
      return [];
    }
  }
}

class NearbyFoodPlace {
  final String id;
  final String name;
  final String? address;
  final double? rating;
  final int? userRatingCount;
  final String? phoneNumber;
  final LatLng? location;

  const NearbyFoodPlace({
    required this.id,
    required this.name,
    this.address,
    this.rating,
    this.userRatingCount,
    this.phoneNumber,
    this.location,
  });

  factory NearbyFoodPlace.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    return NearbyFoodPlace(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? 'Food stop',
      address: json['address'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      userRatingCount: json['user_rating_count'] as int?,
      phoneNumber: json['phone_number'] as String?,
      location:
          location?['latitude'] != null && location?['longitude'] != null
              ? LatLng(
                (location!['latitude'] as num).toDouble(),
                (location['longitude'] as num).toDouble(),
              )
              : null,
    );
  }
}
