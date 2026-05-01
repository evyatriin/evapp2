import 'obd_models.dart';

/// Rolling-window SOC depletion predictor.
///
/// Feed it (soc, tripDistanceKm) samples at each OBD poll cycle.
/// It uses a simple linear rate over the last [_windowSize] samples
/// to predict when the SOC will reach the user-defined charge threshold.
class SocPredictor {
  static const int _windowSize = 20;
  static const int _minSamples = 5;

  final List<_Sample> _samples = [];

  void addSample({required double socPct, required double tripDistanceKm}) {
    _samples.add(_Sample(
      time: DateTime.now(),
      socPct: socPct,
      distanceKm: tripDistanceKm,
    ));
    if (_samples.length > _windowSize) {
      _samples.removeAt(0);
    }
  }

  void reset() => _samples.clear();

  SocPrediction predict({
    required double thresholdPct,
    double? currentSpeedKph,
  }) {
    if (_samples.length < _minSamples) {
      return SocPrediction.noData(thresholdPct);
    }

    final first = _samples.first;
    final last = _samples.last;

    final distanceDelta = last.distanceKm - first.distanceKm;
    final socDelta = first.socPct - last.socPct; // positive when depleting

    // Not moving or battery is charging/stable
    if (distanceDelta <= 0.1 || socDelta <= 0) {
      return SocPrediction(
        thresholdPct: thresholdPct,
        hasData: true,
        remainingKm: null,
        remainingMinutes: null,
        depletionRatePerKm: null,
      );
    }

    final ratePerKm = socDelta / distanceDelta; // % depleted per km
    final socAboveThreshold = last.socPct - thresholdPct;

    if (socAboveThreshold <= 0) {
      // Already at or below threshold
      return SocPrediction(
        thresholdPct: thresholdPct,
        hasData: true,
        remainingKm: 0,
        remainingMinutes: 0,
        depletionRatePerKm: ratePerKm,
      );
    }

    final remainingKm = socAboveThreshold / ratePerKm;

    double? remainingMinutes;
    if (currentSpeedKph != null && currentSpeedKph > 2) {
      remainingMinutes = (remainingKm / currentSpeedKph) * 60;
    }

    return SocPrediction(
      thresholdPct: thresholdPct,
      hasData: true,
      remainingKm: remainingKm,
      remainingMinutes: remainingMinutes,
      depletionRatePerKm: ratePerKm,
    );
  }
}

class _Sample {
  final DateTime time;
  final double socPct;
  final double distanceKm;

  const _Sample({
    required this.time,
    required this.socPct,
    required this.distanceKm,
  });
}
