import 'vehicle_template_model.dart';

class VehicleProfile {
  final String id;
  final String userId;
  final String brand;
  final String model;
  final String variant;
  final double rangeEfficiency; // 0.5 to 1.0
  final String? imageUrl;
  final String? photoUrl; // Supabase Storage URL
  final List<String> preferredChargingNetworks;
  final bool isPrimary;

  const VehicleProfile({
    required this.id,
    required this.userId,
    required this.brand,
    required this.model,
    required this.variant,
    required this.rangeEfficiency,
    this.imageUrl,
    this.photoUrl,
    this.preferredChargingNetworks = const [],
    this.isPrimary = false,
  });

  VehicleProfile copyWith({
    String? id,
    String? userId,
    String? brand,
    String? model,
    String? variant,
    double? rangeEfficiency,
    String? imageUrl,
    String? photoUrl,
    List<String>? preferredChargingNetworks,
    bool? isPrimary,
  }) {
    return VehicleProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      variant: variant ?? this.variant,
      rangeEfficiency: rangeEfficiency ?? this.rangeEfficiency,
      imageUrl: imageUrl ?? this.imageUrl,
      photoUrl: photoUrl ?? this.photoUrl,
      preferredChargingNetworks: preferredChargingNetworks ?? this.preferredChargingNetworks,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }
  
  double get ratedRangeKm => ratedRangeKmFor(brand, model);

  /// Real-world expected range, derived from the model's rated range
  /// scaled by the user's efficiency factor.
  double get estimatedRange => ratedRangeKm * rangeEfficiency;

  // JSON serialization
  factory VehicleProfile.fromJson(Map<String, dynamic> json) {
    return VehicleProfile(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      brand: json['brand'] as String,
      model: json['model'] as String,
      variant: json['variant'] as String,
      rangeEfficiency: (json['range_efficiency'] as num).toDouble(),
      imageUrl: json['image_url'] as String?,
      photoUrl: json['photo_url'] as String?,
      preferredChargingNetworks: (json['preferred_charging_networks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'brand': brand,
      'model': model,
      'variant': variant,
      'range_efficiency': rangeEfficiency,
      'image_url': imageUrl,
      'photo_url': photoUrl,
      'preferred_charging_networks': preferredChargingNetworks,
      'is_primary': isPrimary,
    };
  }
}
