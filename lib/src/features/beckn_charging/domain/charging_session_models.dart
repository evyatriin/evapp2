enum SessionStatus {
  idle,
  starting,
  charging,
  stopping,
  awaitingPayment,
  paymentConfirmed,
  completed,
  failed,
}

enum PaymentType {
  preFulfillment,
  onFulfillment,
}

enum ConnectorType {
  ccs2,
  chademo,
  type2,
  type1,
}

class MeterReading {
  const MeterReading({
    required this.energyKwh,
    required this.costInr,
    required this.currentAmps,
    required this.voltageVolts,
    required this.powerKw,
    required this.socPercent,
    required this.chargingRateInrPerKwh,
    required this.timestamp,
  });

  final double energyKwh;
  final double costInr;
  final double currentAmps;
  final double voltageVolts;
  final double powerKw;
  final double socPercent;
  final double chargingRateInrPerKwh;
  final DateTime timestamp;

  factory MeterReading.fromJson(Map<String, dynamic> json) {
    return MeterReading(
      energyKwh: (json['energy_kwh'] as num?)?.toDouble() ?? 0.0,
      costInr: (json['cost_inr'] as num?)?.toDouble() ?? 0.0,
      currentAmps: (json['current_amps'] as num?)?.toDouble() ?? 0.0,
      voltageVolts: (json['voltage_volts'] as num?)?.toDouble() ?? 0.0,
      powerKw: (json['power_kw'] as num?)?.toDouble() ?? 0.0,
      socPercent: (json['soc_percent'] as num?)?.toDouble() ?? 0.0,
      chargingRateInrPerKwh:
          (json['charging_rate_inr_per_kwh'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}

class ChargerDetails {
  const ChargerDetails({
    required this.chargerId,
    required this.connectorId,
    required this.chargerName,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.powerKw,
    required this.connectorType,
    required this.chargingRateInrPerKwh,
    required this.canStartImmediately,
  });

  final String chargerId;
  final String connectorId;
  final String chargerName;
  final String locationName;
  final double latitude;
  final double longitude;
  final double powerKw;
  final String connectorType;
  final double chargingRateInrPerKwh;
  final bool canStartImmediately;

  factory ChargerDetails.fromJson(Map<String, dynamic> json) {
    return ChargerDetails(
      chargerId: json['charger_id'] as String? ?? '',
      connectorId: json['connector_id'] as String? ?? '',
      chargerName: json['charger_name'] as String? ?? 'Unknown Charger',
      locationName: json['location_name'] as String? ?? 'Unknown Location',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      powerKw: (json['power_kw'] as num?)?.toDouble() ?? 0.0,
      connectorType: json['connector_type'] as String? ?? 'Unknown',
      chargingRateInrPerKwh:
          (json['charging_rate_inr_per_kwh'] as num?)?.toDouble() ?? 0.0,
      canStartImmediately: json['can_start_immediately'] as bool? ?? false,
    );
  }
}

class ChargingSession {
  const ChargingSession({
    required this.sessionId,
    required this.chargerId,
    required this.connectorId,
    required this.status,
    required this.startTime,
    this.latestReading,
    this.errorMessage,
    this.paymentUri,
    this.finalCostInr,
  });

  final String sessionId;
  final String chargerId;
  final String connectorId;
  final SessionStatus status;
  final DateTime startTime;
  final MeterReading? latestReading;
  final String? errorMessage;
  final String? paymentUri;
  final double? finalCostInr;

  ChargingSession copyWith({
    String? sessionId,
    String? chargerId,
    String? connectorId,
    SessionStatus? status,
    DateTime? startTime,
    MeterReading? latestReading,
    String? errorMessage,
    String? paymentUri,
    double? finalCostInr,
  }) {
    return ChargingSession(
      sessionId: sessionId ?? this.sessionId,
      chargerId: chargerId ?? this.chargerId,
      connectorId: connectorId ?? this.connectorId,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      latestReading: latestReading ?? this.latestReading,
      errorMessage: errorMessage ?? this.errorMessage,
      paymentUri: paymentUri ?? this.paymentUri,
      finalCostInr: finalCostInr ?? this.finalCostInr,
    );
  }
}

class SessionStartRequest {
  const SessionStartRequest({
    required this.chargerId,
    required this.connectorId,
    required this.chargingRateInrPerKwh,
    required this.idempotencyKey,
    this.vehicleId,
  });

  final String chargerId;
  final String connectorId;
  final double chargingRateInrPerKwh;
  final String? vehicleId;
  final String idempotencyKey;

  Map<String, dynamic> toJson() {
    return {
      'charger_id': chargerId,
      'connector_id': connectorId,
      'charging_rate_inr_per_kwh': chargingRateInrPerKwh,
      'idempotency_key': idempotencyKey,
      if (vehicleId != null) 'vehicle_id': vehicleId,
    };
  }
}
