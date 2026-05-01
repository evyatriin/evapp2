import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum ObdTransport { ble, classicBluetooth }

enum ObdConnectionStage {
  idle,
  scanning,
  connecting,
  connected,
  unsupported,
  bluetoothOff,
  error,
}

class ObdScanDevice {
  final String id;
  final String name;
  final int rssi;
  final bool isConnectable;
  final ObdTransport transport;
  final String? macAddress;

  const ObdScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isConnectable,
    required this.transport,
    this.macAddress,
  });

  factory ObdScanDevice.fromScanResult(ScanResult result) {
    final advertisedName = result.device.advName.trim();
    final platformName = result.device.platformName.trim();
    final resolvedName =
        advertisedName.isNotEmpty
            ? advertisedName
            : (platformName.isNotEmpty ? platformName : 'Unnamed OBD Adapter');

    return ObdScanDevice(
      id: result.device.remoteId.str,
      name: resolvedName,
      rssi: result.rssi,
      isConnectable: result.advertisementData.connectable,
      transport: ObdTransport.ble,
    );
  }

  factory ObdScanDevice.classic({
    required String address,
    required String name,
    int rssi = 0,
    bool isConnectable = true,
  }) {
    return ObdScanDevice(
      id: address,
      name: name,
      rssi: rssi,
      isConnectable: isConnectable,
      transport: ObdTransport.classicBluetooth,
      macAddress: address,
    );
  }

  String get transportLabel => switch (transport) {
    ObdTransport.ble => 'BLE',
    ObdTransport.classicBluetooth => 'Classic Bluetooth',
  };
}

class ObdDiagnosticEntry {
  final DateTime timestamp;
  final String phase;
  final String message;

  const ObdDiagnosticEntry({
    required this.timestamp,
    required this.phase,
    required this.message,
  });
}

// ─── SOC charge-threshold prediction ─────────────────────────────────────────

class SocPrediction {
  /// km remaining before SOC drops to [thresholdPct]. null = no data / not depleting.
  final double? remainingKm;

  /// Estimated minutes remaining. null = no speed data.
  final double? remainingMinutes;

  /// Current SOC depletion rate in % per km. null = insufficient data.
  final double? depletionRatePerKm;

  /// The target SOC % the user wants to charge at.
  final double thresholdPct;

  /// False until enough samples collected.
  final bool hasData;

  const SocPrediction({
    required this.thresholdPct,
    required this.hasData,
    this.remainingKm,
    this.remainingMinutes,
    this.depletionRatePerKm,
  });

  factory SocPrediction.noData(double threshold) =>
      SocPrediction(thresholdPct: threshold, hasData: false);

  String get summary {
    if (!hasData) return 'Gathering SOC data… drive to begin prediction.';
    if (remainingKm == null) {
      return 'SOC is steady — no depletion detected while stationary.';
    }
    if (remainingKm! <= 0) return 'Charge now — SOC is at or below ${thresholdPct.toStringAsFixed(0)}%!';
    final km = remainingKm!.toStringAsFixed(0);
    final mins = remainingMinutes != null
        ? ' (~${remainingMinutes!.toStringAsFixed(0)} min)'
        : '';
    return '~$km km$mins until SOC drops to ${thresholdPct.toStringAsFixed(0)}%';
  }

  bool get isUrgent => hasData && remainingKm != null && remainingKm! < 20;
}

// ─── Telemetry snapshot ───────────────────────────────────────────────────────

class ObdTelemetrySnapshot {
  final double? speedKph;
  final double? rpm;
  final double? throttlePercent;
  final double? engineLoadPercent;
  final double? coolantTempC;
  final double? intakeTempC;
  final double? controlModuleVoltage;
  final double? batteryPercent;
  final double? batteryPackVoltage;
  final double? batteryCurrent;
  final double? batteryPowerKw;
  final double? batteryTempC;
  final double? cellDeltaMv;
  final double? estimatedSohPercent;
  // GPS-derived fields (more reliable than OBD for EVs)
  final double? gpsSpeedKph;
  final double? elevationM;
  final double? gradePct; // road grade in %
  final DateTime timestamp;
  final String sourceSummary;
  final String? evProfileName;
  final int enhancedMetricCount;

  const ObdTelemetrySnapshot({
    required this.timestamp,
    required this.sourceSummary,
    required this.enhancedMetricCount,
    this.speedKph,
    this.rpm,
    this.throttlePercent,
    this.engineLoadPercent,
    this.coolantTempC,
    this.intakeTempC,
    this.controlModuleVoltage,
    this.batteryPercent,
    this.batteryPackVoltage,
    this.batteryCurrent,
    this.batteryPowerKw,
    this.batteryTempC,
    this.cellDeltaMv,
    this.estimatedSohPercent,
    this.gpsSpeedKph,
    this.elevationM,
    this.gradePct,
    this.evProfileName,
  });

  /// Effective speed: GPS preferred, OBD as fallback.
  double? get effectiveSpeedKph => gpsSpeedKph ?? speedKph;

  factory ObdTelemetrySnapshot.empty() => ObdTelemetrySnapshot(
    timestamp: DateTime.now(),
    sourceSummary: 'Connect to an OBD-II adapter to start streaming telemetry.',
    enhancedMetricCount: 0,
  );

  ObdTelemetrySnapshot copyWith({
    double? speedKph,
    double? rpm,
    double? throttlePercent,
    double? engineLoadPercent,
    double? coolantTempC,
    double? intakeTempC,
    double? controlModuleVoltage,
    double? batteryPercent,
    double? batteryPackVoltage,
    double? batteryCurrent,
    double? batteryPowerKw,
    double? batteryTempC,
    double? cellDeltaMv,
    double? estimatedSohPercent,
    double? gpsSpeedKph,
    double? elevationM,
    double? gradePct,
    DateTime? timestamp,
    String? sourceSummary,
    String? evProfileName,
    int? enhancedMetricCount,
  }) {
    return ObdTelemetrySnapshot(
      speedKph: speedKph ?? this.speedKph,
      rpm: rpm ?? this.rpm,
      throttlePercent: throttlePercent ?? this.throttlePercent,
      engineLoadPercent: engineLoadPercent ?? this.engineLoadPercent,
      coolantTempC: coolantTempC ?? this.coolantTempC,
      intakeTempC: intakeTempC ?? this.intakeTempC,
      controlModuleVoltage: controlModuleVoltage ?? this.controlModuleVoltage,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      batteryPackVoltage: batteryPackVoltage ?? this.batteryPackVoltage,
      batteryCurrent: batteryCurrent ?? this.batteryCurrent,
      batteryPowerKw: batteryPowerKw ?? this.batteryPowerKw,
      batteryTempC: batteryTempC ?? this.batteryTempC,
      cellDeltaMv: cellDeltaMv ?? this.cellDeltaMv,
      estimatedSohPercent: estimatedSohPercent ?? this.estimatedSohPercent,
      gpsSpeedKph: gpsSpeedKph ?? this.gpsSpeedKph,
      elevationM: elevationM ?? this.elevationM,
      gradePct: gradePct ?? this.gradePct,
      timestamp: timestamp ?? this.timestamp,
      sourceSummary: sourceSummary ?? this.sourceSummary,
      evProfileName: evProfileName ?? this.evProfileName,
      enhancedMetricCount: enhancedMetricCount ?? this.enhancedMetricCount,
    );
  }
}

class DriverAnalytics {
  final double smoothDrivingScore;
  final double efficiencyScore;
  final int harshAccelerationEvents;
  final int harshBrakingEvents;
  final double averageSpeedKph;
  final double peakSpeedKph;
  final double tripDistanceKm;
  final Duration idleTime;

  const DriverAnalytics({
    required this.smoothDrivingScore,
    required this.efficiencyScore,
    required this.harshAccelerationEvents,
    required this.harshBrakingEvents,
    required this.averageSpeedKph,
    required this.peakSpeedKph,
    required this.tripDistanceKm,
    required this.idleTime,
  });

  factory DriverAnalytics.empty() => const DriverAnalytics(
    smoothDrivingScore: 100,
    efficiencyScore: 100,
    harshAccelerationEvents: 0,
    harshBrakingEvents: 0,
    averageSpeedKph: 0,
    peakSpeedKph: 0,
    tripDistanceKm: 0,
    idleTime: Duration.zero,
  );
}

class ObdSessionState {
  final BluetoothAdapterState adapterState;
  final ObdConnectionStage stage;
  final bool permissionsGranted;
  final bool isScanning;
  final List<ObdScanDevice> scanDevices;
  final ObdScanDevice? selectedDevice;
  final ObdTelemetrySnapshot telemetry;
  final DriverAnalytics analytics;
  final String statusMessage;
  final String compatibilityHint;
  final List<ObdDiagnosticEntry> diagnostics;
  final SocPrediction? socPrediction;
  final double chargeThresholdPct; // user-set SOC % to charge at

  const ObdSessionState({
    required this.adapterState,
    required this.stage,
    required this.permissionsGranted,
    required this.isScanning,
    required this.scanDevices,
    required this.selectedDevice,
    required this.telemetry,
    required this.analytics,
    required this.statusMessage,
    required this.compatibilityHint,
    required this.diagnostics,
    this.socPrediction,
    this.chargeThresholdPct = 20,
  });

  factory ObdSessionState.initial() => ObdSessionState(
    adapterState: BluetoothAdapterState.unknown,
    stage: ObdConnectionStage.idle,
    permissionsGranted: false,
    isScanning: false,
    scanDevices: const [],
    selectedDevice: null,
    telemetry: ObdTelemetrySnapshot.empty(),
    analytics: DriverAnalytics.empty(),
    statusMessage: 'Bluetooth permissions are required to scan for adapters.',
    compatibilityHint:
        'Best results come from ELM327-compatible adapters. On Android, both BLE and classic Bluetooth adapters are supported, and the app now attempts experimental EV battery UDS probes for supported vehicles.',
    diagnostics: const [],
  );

  ObdSessionState copyWith({
    BluetoothAdapterState? adapterState,
    ObdConnectionStage? stage,
    bool? permissionsGranted,
    bool? isScanning,
    List<ObdScanDevice>? scanDevices,
    ObdScanDevice? selectedDevice,
    bool clearSelectedDevice = false,
    ObdTelemetrySnapshot? telemetry,
    DriverAnalytics? analytics,
    String? statusMessage,
    String? compatibilityHint,
    List<ObdDiagnosticEntry>? diagnostics,
    SocPrediction? socPrediction,
    double? chargeThresholdPct,
  }) {
    return ObdSessionState(
      adapterState: adapterState ?? this.adapterState,
      stage: stage ?? this.stage,
      permissionsGranted: permissionsGranted ?? this.permissionsGranted,
      isScanning: isScanning ?? this.isScanning,
      scanDevices: scanDevices ?? this.scanDevices,
      selectedDevice:
          clearSelectedDevice ? null : (selectedDevice ?? this.selectedDevice),
      telemetry: telemetry ?? this.telemetry,
      analytics: analytics ?? this.analytics,
      statusMessage: statusMessage ?? this.statusMessage,
      compatibilityHint: compatibilityHint ?? this.compatibilityHint,
      diagnostics: diagnostics ?? this.diagnostics,
      socPrediction: socPrediction ?? this.socPrediction,
      chargeThresholdPct: chargeThresholdPct ?? this.chargeThresholdPct,
    );
  }
}
