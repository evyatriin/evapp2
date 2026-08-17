import 'route_model.dart';

/// Breaks down a route's estimated cost into itemised components so the user
/// can see exactly what they're paying for BEFORE pressing "Start Navigation".
///
/// Inputs come from the route model (backend-computed) — we don't re-invent
/// the routing maths, we just present the data more transparently.
class TripCostCalculator {
  /// Approximate energy consumption for Indian EVs (kWh per km).
  /// Real-world figure derived from manufacturer specs discounted ~15%.
  static const double _kDefaultConsumptionKwhPerKm = 0.15;

  /// Default ₹/kWh when no per-stop cost is available.
  static const double _kDefaultRatePerKwh = 18.0;

  static TripCostBreakdown calculate(RouteModel route) {
    final chargingStops = route.stops
        .where((s) => s.type == StopType.charging)
        .toList();

    // Per-stop cost breakdown from backend data
    final stopCosts = chargingStops.map((s) {
      return ChargingStopCost(
        name: s.name,
        costRs: s.cost ?? 0.0,
        durationMin: s.chargeDurationMin ?? 0,
        arrivalSoc: s.arrivalSoc ?? 0,
        departureSoc: s.departureSoc ?? (s.targetSoc ?? 0),
      );
    }).toList();

    // Total charging cost = sum of per-stop costs from backend
    final double chargingCostRs = stopCosts.fold(0.0, (sum, s) => sum + s.costRs);

    // If per-stop costs sum to 0 but route has an overall estimatedCost, use that
    final double totalCostRs = chargingCostRs > 0
        ? chargingCostRs
        : route.estimatedCost;

    // Estimated energy consumed (kWh) from the total distance
    final double kwhConsumed =
        route.totalDistanceKm * _kDefaultConsumptionKwhPerKm;

    // Effective ₹/kWh rate — back-calculated from the total cost
    final double effectiveRatePerKwh = kwhConsumed > 0
        ? totalCostRs / kwhConsumed
        : _kDefaultRatePerKwh;

    return TripCostBreakdown(
      totalRs: totalCostRs,
      chargingCostRs: chargingCostRs,
      kwhConsumed: kwhConsumed,
      effectiveRatePerKwh: effectiveRatePerKwh,
      stops: stopCosts,
      hasPerStopBreakdown: chargingCostRs > 0,
    );
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class TripCostBreakdown {
  /// Total trip charging cost in ₹.
  final double totalRs;

  /// Sum of per-stop costs (may equal [totalRs] or 0 if no per-stop data).
  final double chargingCostRs;

  /// Estimated kWh consumed over the full trip.
  final double kwhConsumed;

  /// Effective ₹/kWh averaged over the trip.
  final double effectiveRatePerKwh;

  /// Per charging-stop breakdown.
  final List<ChargingStopCost> stops;

  /// True when we have individual stop costs from the backend.
  final bool hasPerStopBreakdown;

  const TripCostBreakdown({
    required this.totalRs,
    required this.chargingCostRs,
    required this.kwhConsumed,
    required this.effectiveRatePerKwh,
    required this.stops,
    required this.hasPerStopBreakdown,
  });

  /// Total number of charging stops.
  int get stopCount => stops.length;

  /// Formatted total for display (e.g. "₹450").
  String get formattedTotal => '₹${totalRs.toStringAsFixed(0)}';

  /// Formatted kWh consumed (e.g. "45.0 kWh").
  String get formattedKwh => '${kwhConsumed.toStringAsFixed(1)} kWh';

  /// Formatted effective rate (e.g. "₹18/kWh").
  String get formattedRate => '~₹${effectiveRatePerKwh.toStringAsFixed(0)}/kWh';
}

class ChargingStopCost {
  final String name;
  final double costRs;
  final int durationMin;
  final int arrivalSoc;
  final int departureSoc;

  const ChargingStopCost({
    required this.name,
    required this.costRs,
    required this.durationMin,
    required this.arrivalSoc,
    required this.departureSoc,
  });

  /// SoC gained at this stop.
  int get socGained => departureSoc - arrivalSoc;

  String get formattedCost => '₹${costRs.toStringAsFixed(0)}';
}
