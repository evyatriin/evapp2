class VehicleTemplate {
  final String id;
  final String brand;
  final String model;
  final String variant;
  final double rangeEfficiency;
  final String imageUrl;
  final List<String> preferredChargingNetworks;

  VehicleTemplate({
    required this.id,
    required this.brand,
    required this.model,
    required this.variant,
    required this.rangeEfficiency,
    required this.imageUrl,
    required this.preferredChargingNetworks,
  });

  factory VehicleTemplate.fromJson(Map<String, dynamic> json) {
    return VehicleTemplate(
      id: json['id'],
      brand: json['brand'],
      model: json['model'],
      variant: json['variant'],
      rangeEfficiency: json['range_efficiency'].toDouble(),
      imageUrl: json['image_url'],
      preferredChargingNetworks: List<String>.from(json['preferred_charging_networks'] ?? []),
    );
  }
}
