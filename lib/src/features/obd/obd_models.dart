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
    this.evProfileName,
  });

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
    );
  }
}
