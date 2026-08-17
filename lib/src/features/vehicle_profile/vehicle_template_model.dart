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
  final double? batteryKwh;
  final double? certifiedRangeKm;
  final String? rangeCycle;
  final double? realWorldRangeKm;
  final double? dcFastChargeKw;
  final double? acChargeKw;
  final String? connectorType;
  final double? priceMin;
  final double? priceMax;
  final String launchStatus;
  final String imageUrl;
  final String? sourceUrl;
  final DateTime? lastSeenAt;
  final DateTime? verifiedAt;
  final double confidenceScore;
  final List<String> preferredChargingNetworks;

  VehicleTemplate({
    required this.id,
    required this.brand,
    required this.model,
    required this.variant,
    required this.rangeEfficiency,
    this.batteryKwh,
    this.certifiedRangeKm,
    this.rangeCycle,
    this.realWorldRangeKm,
    this.dcFastChargeKw,
    this.acChargeKw,
    this.connectorType,
    this.priceMin,
    this.priceMax,
    this.launchStatus = 'available',
    required this.imageUrl,
    this.sourceUrl,
    this.lastSeenAt,
    this.verifiedAt,
    this.confidenceScore = 0.6,
    required this.preferredChargingNetworks,
  });

  double get ratedRangeKm =>
      realWorldRangeKm ?? certifiedRangeKm ?? ratedRangeKmFor(brand, model);

  factory VehicleTemplate.fromJson(Map<String, dynamic> json) {
    return VehicleTemplate(
      id: json['id'],
      brand: json['brand'],
      model: json['model'],
      variant: json['variant'],
      rangeEfficiency: json['range_efficiency'].toDouble(),
      batteryKwh: _toDouble(json['battery_kwh']),
      certifiedRangeKm: _toDouble(json['certified_range_km']),
      rangeCycle: json['range_cycle'] as String?,
      realWorldRangeKm: _toDouble(json['real_world_range_km']),
      dcFastChargeKw: _toDouble(json['dc_fast_charge_kw']),
      acChargeKw: _toDouble(json['ac_charge_kw']),
      connectorType: json['connector_type'] as String?,
      priceMin: _toDouble(json['price_min']),
      priceMax: _toDouble(json['price_max']),
      launchStatus: json['launch_status'] as String? ?? 'available',
      imageUrl: json['image_url'],
      sourceUrl: json['source_url'] as String?,
      lastSeenAt: _toDate(json['last_seen_at']),
      verifiedAt: _toDate(json['verified_at']),
      confidenceScore: _toDouble(json['confidence_score']) ?? 0.6,
      preferredChargingNetworks:
          List<String>.from(json['preferred_charging_networks'] ?? []),
    );
  }
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
