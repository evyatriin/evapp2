import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../vehicle_profile/vehicle_provider.dart';
import 'obd_history_service.dart';
import 'obd_models.dart';
import 'obd_service.dart';

final obdSessionControllerProvider =
    NotifierProvider<ObdSessionController, ObdSessionState>(
      ObdSessionController.new,
    );

class ObdSessionController extends Notifier<ObdSessionState> {
  final ObdService _service = ObdService();
  final DriverAnalyticsCalculator _analyticsCalculator =
      const DriverAnalyticsCalculator();
  static const int _maxDiagnosticEntries = 80;

  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  Timer? _pollingTimer;

  ObdTelemetrySnapshot _previousSnapshot = ObdTelemetrySnapshot.empty();
  int _pollCycle = 0;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  static const int _historyCheckpointFrequency = 5;
  List<ObdCommandResult> _cachedEnhancedResults = const [];
  String? _sessionId;
  DateTime? _sessionStartedAt;

  @override
  ObdSessionState build() {
    ref.onDispose(_disposeResources);
    Future<void>.microtask(_init);
    return ObdSessionState.initial();
  }

  Future<void> _init() async {
    try {
      _service.bindDiagnostics(_recordDiagnostic);
      _recordDiagnostic('setup', 'OBD controller initialization started.');
      _service.bindScanStreams(
        onScanResults: (devices) {
          _recordDiagnostic(
            'scan',
            'Scan results updated with ${devices.length} visible adapter(s).',
          );
          state = state.copyWith(scanDevices: devices);
        },
        onScanningChanged: (isScanning) {
          _recordDiagnostic(
            'scan',
            isScanning ? 'Bluetooth scan started.' : 'Bluetooth scan stopped.',
          );
          state = state.copyWith(
            isScanning: isScanning,
            stage: isScanning ? ObdConnectionStage.scanning : state.stage,
            statusMessage:
                isScanning
                    ? 'Scanning for nearby OBD-II adapters...'
                    : state.statusMessage,
          );
        },
      );
      _adapterSubscription = FlutterBluePlus.adapterState.listen((adapterState) {
        _recordDiagnostic('adapter', 'Bluetooth adapter state is $adapterState.');
        final nextStage = switch (adapterState) {
          BluetoothAdapterState.off => ObdConnectionStage.bluetoothOff,
          _ => state.stage,
        };
        final message = switch (adapterState) {
          BluetoothAdapterState.on =>
            state.selectedDevice == null
                ? 'Bluetooth is on. Scan and connect to your OBD adapter.'
                : state.statusMessage,
          BluetoothAdapterState.off =>
            'Turn on Bluetooth to connect to your OBD adapter.',
          _ => state.statusMessage,
        };
        state = state.copyWith(
          adapterState: adapterState,
          stage: nextStage,
          statusMessage: message,
        );
      });
      final support = await _service.ensurePermissions();
      _recordDiagnostic(
        'permissions',
        'Permissions granted=${support.permissionsGranted}, BLE=${support.bleSupported}, classic=${support.classicSupported}.',
      );

      if (!support.permissionsGranted) {
        _recordDiagnostic(
          'permissions',
          'Bluetooth permissions were denied by the user or system.',
        );
        state = state.copyWith(
          permissionsGranted: false,
          stage: ObdConnectionStage.error,
          statusMessage:
              'Bluetooth permissions were denied. Allow them in Settings to use telemetry.',
        );
        return;
      }

      state = state.copyWith(
        permissionsGranted: true,
        stage:
            support.anySupported
                ? ObdConnectionStage.idle
                : ObdConnectionStage.unsupported,
        statusMessage:
            support.anySupported
                ? 'Ready to scan for OBD-II adapters.'
                : 'Bluetooth is not supported on this device.',
      );
      _recordDiagnostic('setup', 'OBD controller initialization finished.');
    } catch (e) {
      _recordDiagnostic('setup', 'Initialization failed: $e');
      state = state.copyWith(
        stage: ObdConnectionStage.error,
        statusMessage:
            'OBD setup could not start on this device yet. Check Bluetooth permissions and try again. Details: $e',
      );
    }
  }

  Future<void> ensureSetup() async {
    await _init();
  }

  Future<void> retryPermissionSetup() async {
    final support = await _service.ensurePermissions();
    _recordDiagnostic(
      'permissions',
      'Retried permission setup: granted=${support.permissionsGranted}.',
    );
    final granted = support.permissionsGranted;
    state = state.copyWith(
      permissionsGranted: granted,
      stage:
          !granted
              ? ObdConnectionStage.error
              : support.anySupported
              ? ObdConnectionStage.idle
              : ObdConnectionStage.unsupported,
      statusMessage:
          granted
              ? 'Permissions granted. You can scan now.'
              : 'Bluetooth permissions are still missing.',
    );
  }

  Future<void> startScan() async {
    if (!state.permissionsGranted) {
      _recordDiagnostic(
        'scan',
        'Scan requested before permissions were granted; retrying permissions.',
      );
      await retryPermissionSetup();
      return;
    }

    if (state.adapterState == BluetoothAdapterState.off) {
      _recordDiagnostic('scan', 'Scan blocked because Bluetooth is turned off.');
      state = state.copyWith(
        isScanning: false,
        stage: ObdConnectionStage.bluetoothOff,
        statusMessage: 'Bluetooth is off. Turn it on, then scan again.',
      );
      return;
    }

    state = state.copyWith(
      isScanning: true,
      stage: ObdConnectionStage.scanning,
      statusMessage: 'Scanning for nearby OBD-II adapters...',
    );
    _recordDiagnostic('scan', 'Starting adapter scan.');

    try {
      await _service.startScan();
    } catch (e) {
      _recordDiagnostic('scan', 'Scan failed: $e');
      final bluetoothOff =
          e.toString().toLowerCase().contains('bluetooth must be turned on');
      state = state.copyWith(
        isScanning: false,
        stage:
            bluetoothOff
                ? ObdConnectionStage.bluetoothOff
                : ObdConnectionStage.error,
        statusMessage:
            bluetoothOff
                ? 'Bluetooth is off. Turn it on, then scan again.'
                : 'Could not start scanning: $e',
      );
    }
  }

  Future<void> stopScan() async {
    await _service.stopScan();
    _recordDiagnostic('scan', 'Scan stopped by user.');
    state = state.copyWith(
      isScanning: false,
      stage:
          state.selectedDevice == null
              ? ObdConnectionStage.idle
              : ObdConnectionStage.connected,
    );
  }

  Future<void> connect(ObdScanDevice device) async {
    try {
      _recordDiagnostic(
        'connect',
        'Connecting to ${device.name} over ${device.transportLabel}.',
      );
      state = state.copyWith(
        selectedDevice: device,
        stage: ObdConnectionStage.connecting,
        statusMessage: 'Connecting to ${device.name}...',
      );

      await _service.connect(device);
      _previousSnapshot = ObdTelemetrySnapshot.empty();
      _cachedEnhancedResults = const [];
      _pollCycle = 0;
      _sessionStartedAt = DateTime.now();
      _sessionId = _sessionStartedAt!.millisecondsSinceEpoch.toString();
      _recordDiagnostic(
        'connect',
        'Connection established to ${device.name}; starting telemetry polling.',
      );
      state = state.copyWith(
        stage: ObdConnectionStage.connected,
        statusMessage: 'Connected to ${device.name}. Polling live telemetry...',
      );
      _startPolling();
    } catch (e) {
      _recordDiagnostic('connect', 'Connection failed: $e');
      state = state.copyWith(
        stage: ObdConnectionStage.error,
        statusMessage: 'Failed to connect: $e',
      );
    }
  }

  Future<void> disconnect() async {
    _recordDiagnostic('connect', 'Disconnect requested by user.');
    await _persistHistorySnapshot();
    _pollingTimer?.cancel();
    await _service.disconnect();
    _cachedEnhancedResults = const [];
    _pollCycle = 0;
    _sessionId = null;
    _sessionStartedAt = null;
    state = state.copyWith(
      stage: ObdConnectionStage.idle,
      clearSelectedDevice: true,
      statusMessage: 'Disconnected from adapter.',
    );
  }

  void clearDiagnostics() {
    state = state.copyWith(diagnostics: const []);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollOnce();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollOnce(),
    );
  }

  Future<void> _pollOnce() async {
    try {
      _recordDiagnostic('poll', 'Polling live telemetry.');
      final primaryVehicle = ref.read(vehicleProvider.notifier).primaryVehicle;
      final standardResults = await _service.pollStandardTelemetry();
      final shouldRefreshEnhanced =
          _cachedEnhancedResults.isEmpty || _pollCycle % 3 == 0;
      if (shouldRefreshEnhanced) {
        _cachedEnhancedResults = await _service.pollEnhancedTelemetry(
          vehicleBrand: primaryVehicle?.brand,
          vehicleModel: primaryVehicle?.model,
        );
      }
      _pollCycle += 1;
      _consecutiveErrors = 0;
      final results = [...standardResults, ..._cachedEnhancedResults];
      final nextSnapshot = _buildSnapshot(results);
      final analytics = _analyticsCalculator.update(
        current: state.analytics,
        previous: _previousSnapshot,
        next: nextSnapshot,
      );

      _previousSnapshot = nextSnapshot;
      _recordDiagnostic(
        'poll',
        'Polling succeeded with $enhancedMetricCountLabel',
      );
      state = state.copyWith(
        stage: ObdConnectionStage.connected,
        telemetry: nextSnapshot.copyWith(
          estimatedSohPercent: _estimateSoh(
            snapshot: nextSnapshot,
            analytics: analytics,
          ),
        ),
        analytics: analytics,
        statusMessage:
            'Streaming live OBD telemetry from ${state.selectedDevice?.name ?? 'adapter'}.',
      );

      if (_pollCycle % _historyCheckpointFrequency == 0) {
        await _persistHistorySnapshot();
      }
    } catch (e) {
      _consecutiveErrors += 1;
      _recordDiagnostic(
        'poll',
        'Polling error $_consecutiveErrors/$_maxConsecutiveErrors: $e',
      );
      if (_consecutiveErrors >= _maxConsecutiveErrors) {
        _pollingTimer?.cancel();
        state = state.copyWith(
          stage: ObdConnectionStage.error,
          statusMessage:
              'Telemetry polling stopped after $_consecutiveErrors consecutive errors: $e',
        );
      } else {
        state = state.copyWith(
          statusMessage:
              'Transient error (attempt $_consecutiveErrors/$_maxConsecutiveErrors), retrying...',
        );
      }
    }
  }

  String get enhancedMetricCountLabel {
    final count = _cachedEnhancedResults.where((result) => result.supported).length;
    return '$count enhanced metric${count == 1 ? '' : 's'}';
  }

  ObdTelemetrySnapshot _buildSnapshot(List<ObdCommandResult> results) {
    final values = {for (final result in results) result.key: result};
    final batteryPercent = values['batteryPercent']?.value;
    final controlModuleVoltage = values['controlModuleVoltage']?.value;
    final batteryPackVoltage = values['batteryPackVoltage']?.value;
    final batteryCurrent = values['batteryCurrent']?.value;
    final batteryPowerKw =
        batteryPackVoltage != null && batteryCurrent != null
            ? (batteryPackVoltage * batteryCurrent) / 1000
            : null;
    final enhancedMetricCount =
        [
          'batteryPackVoltage',
          'batteryCurrent',
          'batteryTempC',
          'stateOfHealth',
          'cellDeltaMv',
        ].where((key) => values[key]?.supported == true).length;
    final primaryVehicle = ref.read(vehicleProvider.notifier).primaryVehicle;
    final selectedProfile = _service.resolveEnhancedProfile(
      vehicleBrand: primaryVehicle?.brand,
      vehicleModel: primaryVehicle?.model,
    );
    final evProfileName = selectedProfile?.name;

    return ObdTelemetrySnapshot(
      speedKph: values['speedKph']?.value,
      rpm: values['rpm']?.value,
      throttlePercent: values['throttlePercent']?.value,
      engineLoadPercent: values['engineLoadPercent']?.value,
      coolantTempC: values['coolantTempC']?.value,
      intakeTempC: values['intakeTempC']?.value,
      controlModuleVoltage: controlModuleVoltage,
      batteryPercent: batteryPercent,
      batteryPackVoltage: batteryPackVoltage,
      batteryCurrent: batteryCurrent,
      batteryPowerKw: batteryPowerKw,
      batteryTempC: values['batteryTempC']?.value,
      cellDeltaMv: values['cellDeltaMv']?.value,
      estimatedSohPercent: values['stateOfHealth']?.value,
      evProfileName: evProfileName,
      enhancedMetricCount: enhancedMetricCount,
      timestamp: DateTime.now(),
      sourceSummary:
          enhancedMetricCount > 0
              ? '${selectedProfile?.name ?? 'Enhanced EV battery probes'} returned $enhancedMetricCount enhanced metrics on top of the standard OBD-II feed.'
              : selectedProfile != null
              ? '${selectedProfile.name} is active. Standard OBD-II telemetry is live while enhanced EV battery probes refresh in the background.'
              : 'Live data is coming from standard OBD-II PIDs. No EV-specific battery profile is currently matched for this vehicle.',
    );
  }

  double? _estimateSoh({
    required ObdTelemetrySnapshot snapshot,
    required DriverAnalytics analytics,
  }) {
    if (snapshot.estimatedSohPercent != null) {
      return snapshot.estimatedSohPercent;
    }

    if (snapshot.batteryPercent != null) {
      return snapshot.batteryPercent;
    }

    if (snapshot.cellDeltaMv != null) {
      final cellHealth = (100 - (snapshot.cellDeltaMv! / 4)).clamp(70, 100);
      if (snapshot.batteryTempC != null) {
        final temperaturePenalty = ((snapshot.batteryTempC! - 28).abs() * 0.4)
            .clamp(0, 12);
        return (cellHealth - temperaturePenalty).clamp(60, 100).toDouble();
      }
      return cellHealth.toDouble();
    }

    final primaryVehicle = ref.read(vehicleProvider.notifier).primaryVehicle;
    final factors = <double>[
      if (primaryVehicle != null) primaryVehicle.rangeEfficiency * 100,
      analytics.efficiencyScore,
      analytics.smoothDrivingScore,
      if (snapshot.controlModuleVoltage != null)
        (((snapshot.controlModuleVoltage! - 11.8) / 2.6) * 100).clamp(55, 100),
    ];

    if (factors.isEmpty) return null;
    final average = factors.reduce((a, b) => a + b) / factors.length;
    return math.max(55, math.min(100, average));
  }

  void _disposeResources() {
    unawaited(_persistHistorySnapshot());
    _pollingTimer?.cancel();
    _adapterSubscription?.cancel();
    _service.dispose();
  }

  Future<void> _persistHistorySnapshot() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final sessionId = _sessionId;
    final sessionStartedAt = _sessionStartedAt;

    if (userId == null || userId.isEmpty) {
      return;
    }
    if (sessionId == null || sessionStartedAt == null) {
      return;
    }
    if (state.selectedDevice == null) {
      return;
    }
    if (state.analytics.tripDistanceKm <= 0 &&
        state.telemetry.batteryPercent == null &&
        state.telemetry.speedKph == null) {
      return;
    }

    final entry = buildObdHistoryEntry(
      sessionId: sessionId,
      startedAt: sessionStartedAt,
      telemetry: state.telemetry,
      analytics: state.analytics,
      device: state.selectedDevice,
      userId: userId,
    );

    await ObdHistoryService().upsertCurrentUserEntry(entry);
    ref.invalidate(obdHistoryEntriesProvider);
  }

  void _recordDiagnostic(String phase, String message) {
    final nextEntries = [
      ...state.diagnostics,
      ObdDiagnosticEntry(
        timestamp: DateTime.now(),
        phase: phase,
        message: message,
      ),
    ];
    state = state.copyWith(
      diagnostics:
          nextEntries.length <= _maxDiagnosticEntries
              ? nextEntries
              : nextEntries.sublist(nextEntries.length - _maxDiagnosticEntries),
    );
  }
}
