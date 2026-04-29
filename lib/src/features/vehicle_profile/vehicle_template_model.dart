/// Real-world rated range in km, keyed by "brand|model" (case-insensitive).
/// Sourced from manufacturer claims discounted to typical real-world driving.
/// Fallback used when a model is not in the table.
const double _kFallbackRatedRangeKm = 250;

const Map<String, double> _kRatedRangeKmByBrandModel = {
  // Tata
  'tata|nexon ev':       325,
  'tata|tiago ev':       225,
  'tata|punch ev':       280,
  'tata|tigor ev':       260,
  'tata|curvv ev':       370,

  // MG
  'mg|zs ev':            350,
  'mg|comet ev':         170,
  'mg|windsor ev':       270,

  // Hyundai
  'hyundai|kona electric': 340,
  'hyundai|ioniq 5':     430,

  // Mahindra
  'mahindra|xuv400':     320,
  'mahindra|be 6':       480,
  'mahindra|xev 9e':     530,
  'mahindra|e-verito':   140,

  // BYD
  'byd|atto 3':          390,
  'byd|seal':            510,
  'byd|e6':              360,

  // Tesla
  'tesla|model 3':       480,
  'tesla|model y':       450,
  'tesla|model s':       550,

  // Citroën
  'citroen|ec3':         260,
  'citroën|ec3':         260,
};

double ratedRangeKmFor(String brand, String model) {
  final key = '${brand.trim().toLowerCase()}|${model.trim().toLowerCase()}';
  return _kRatedRangeKmByBrandModel[key] ?? _kFallbackRatedRangeKm;
}

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

  double get ratedRangeKm => ratedRangeKmFor(brand, model);

  factory VehicleTemplate.fromJson(Map<String, dynamic> json) {
    return VehicleTemplate(
      id: json['id'],
      brand: json['brand'],
      model: json['model'],
      variant: json['variant'],
      rangeEfficiency: json['range_efficiency'].toDouble(),
      imageUrl: json['image_url'],
      preferredChargingNetworks:
          List<String>.from(json['preferred_charging_networks'] ?? []),
    );
  }
}
