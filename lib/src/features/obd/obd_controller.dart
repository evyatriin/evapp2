import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../vehicle_profile/vehicle_provider.dart';
import 'obd_history_service.dart';
import 'obd_models.dart';
import 'obd_service.dart';
import 'soc_predictor.dart';

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
  StreamSubscription<Position>? _gpsSubscription;
  Timer? _pollingTimer;

  ObdTelemetrySnapshot _previousSnapshot = ObdTelemetrySnapshot.empty();
  int _pollCycle = 0;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;
  static const int _historyCheckpointFrequency = 5;
  List<ObdCommandResult> _cachedEnhancedResults = const [];
  String? _sessionId;
  DateTime? _sessionStartedAt;
  bool _isPolling = false;

  // GPS-derived fields updated independently of OBD polling
  double? _gpsSpeedKph;
  double? _elevationM;
  double? _gradePct;
  double? _prevGpsLat;
  double? _prevGpsLng;
  double? _prevElevForGrade;
  double _gpsDistanceAccumM = 0; // accumulated since last grade sample

  // SOC prediction
  final SocPredictor _socPredictor = SocPredictor();
  static const String _thresholdPrefKey = 'obd_charge_threshold_pct';

  bool _initialized = false;
  bool _disposed = false;

  @override
  ObdSessionState build() {
    ref.onDispose(_disposeResources);
    Future<void>.microtask(_init);
    return ObdSessionState.initial();
  }

  Future<void> _init() async {
    if (_initialized) return;
    try {
      _service.bindDiagnostics(_recordDiagnostic);
      _recordDiagnostic('setup', 'OBD controller initialization started.');
      _adapterSubscription?.cancel();
      _service.bindScanStreams(
        onScanResults: (devices) {
          if (_disposed) return;
          _recordDiagnostic(
            'scan',
            'Scan results updated with ${devices.length} visible adapter(s).',
          );
          state = state.copyWith(scanDevices: devices);
        },
        onScanningChanged: (isScanning) {
          if (_disposed) return;
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
      final support = await _service.ensurePermissions();
      if (_disposed) return;
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

      if (support.bleSupported) {
        _adapterSubscription = FlutterBluePlus.adapterState.listen(
          (adapterState) {
            if (_disposed) return;
            _recordDiagnostic(
              'adapter',
              'Bluetooth adapter state is $adapterState.',
            );
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
          },
          onError: (Object e) {
            if (_disposed) return;
            _recordDiagnostic('adapter', 'Bluetooth adapter stream failed: $e');
          },
        );
      } else {
        _recordDiagnostic(
          'adapter',
          'BLE adapter stream skipped because BLE is not supported.',
        );
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

      // Load persisted charge threshold
      await _loadChargeThreshold();
      if (_disposed) return;

      _initialized = true;
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
    if (!_initialized) {
      await _init();
      return;
    }
    // Already initialized — just retry permissions
    await retryPermissionSetup();
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

  // ─── GPS ─────────────────────────────────────────────────────────────────

  void _startGpsStream() {
    _gpsSubscription?.cancel();
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // only trigger when moved ≥5 m
      ),
    ).listen(
      _onGpsPosition,
      onError: (Object e) {
        _recordDiagnostic('gps', 'GPS stream error: $e');
      },
    );
    _recordDiagnostic('gps', 'GPS position stream started.');
  }

  void _onGpsPosition(Position pos) {
    _gpsSpeedKph = (pos.speed * 3.6).clamp(0, 300); // m/s → km/h
    _elevationM = pos.altitude;

    // Compute grade over accumulated distance
    final lat = pos.latitude;
    final lng = pos.longitude;

    if (_prevGpsLat != null && _prevGpsLng != null) {
      final segmentM = Geolocator.distanceBetween(
        _prevGpsLat!,
        _prevGpsLng!,
        lat,
        lng,
      );
      _gpsDistanceAccumM += segmentM;
    }
    _prevGpsLat = lat;
    _prevGpsLng = lng;

    // Update grade every ~50 m to smooth out noise
    if (_gpsDistanceAccumM >= 50 &&
        _prevElevForGrade != null &&
        _elevationM != null) {
      final elevDiff = _elevationM! - _prevElevForGrade!;
      _gradePct = (elevDiff / _gpsDistanceAccumM) * 100;
      _prevElevForGrade = _elevationM;
      _gpsDistanceAccumM = 0;
    } else {
      _prevElevForGrade ??= _elevationM;
    }
    // GPS fields are merged into state during the next _pollOnce() cycle
    // to avoid excessive Riverpod rebuilds (position stream fires every 5 m).
  }

  // ─── Charge threshold ────────────────────────────────────────────────────

  Future<void> _loadChargeThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_thresholdPrefKey);
      if (saved != null) {
        state = state.copyWith(chargeThresholdPct: saved);
        _recordDiagnostic(
          'soc',
          'Charge threshold loaded: ${saved.toStringAsFixed(0)}%',
        );
      }
    } catch (e) {
      _recordDiagnostic('soc', 'Could not load charge threshold: $e');
    }
  }

  /// Update threshold in state immediately (call from slider onChanged).
  void setChargeThresholdLive(double pct) {
    final clamped = pct.clamp(5.0, 80.0);
    state = state.copyWith(chargeThresholdPct: clamped);
  }

  /// Persist threshold to disk (call from slider onChangeEnd).
  Future<void> commitChargeThreshold(double pct) async {
    final clamped = pct.clamp(5.0, 80.0);
    state = state.copyWith(chargeThresholdPct: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_thresholdPrefKey, clamped);
    } catch (e) {
      _recordDiagnostic('soc', 'Could not persist charge threshold: $e');
    }
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
      _recordDiagnostic(
        'scan',
        'Scan blocked because Bluetooth is turned off.',
      );
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
      final bluetoothOff = e.toString().toLowerCase().contains(
        'bluetooth must be turned on',
      );
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
      _consecutiveErrors = 0;
      _socPredictor.reset();
      _sessionStartedAt = DateTime.now();
      _sessionId = _sessionStartedAt!.millisecondsSinceEpoch.toString();
      _recordDiagnostic(
        'connect',
        'Connection established to ${device.name}; starting telemetry polling.',
      );
      state = state.copyWith(
        stage: ObdConnectionStage.connected,
        statusMessage: 'Connected to ${device.name}. Polling live telemetry...',
        analytics: DriverAnalytics.empty(),
        socPrediction: SocPrediction.noData(state.chargeThresholdPct),
      );
      _startGpsStream();
      _startPolling();
    } catch (e) {
      _recordDiagnostic('connect', 'Connection failed: $e');
      try {
        await _service.disconnect();
      } catch (cleanupError) {
        _recordDiagnostic(
          'connect',
          'Cleanup after failed connection also failed: $cleanupError',
        );
      }
      _pollingTimer?.cancel();
      _gpsSubscription?.cancel();
      _gpsSubscription = null;
      _cachedEnhancedResults = const [];
      _pollCycle = 0;
      _sessionId = null;
      _sessionStartedAt = null;
      state = state.copyWith(
        stage: ObdConnectionStage.error,
        clearSelectedDevice: true,
        statusMessage: 'Failed to connect: $e',
      );
    }
  }

  Future<void> disconnect() async {
    _recordDiagnostic('connect', 'Disconnect requested by user.');
    unawaited(_persistHistorySnapshot());
    _pollingTimer?.cancel();
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    await _service.disconnect();
    _cachedEnhancedResults = const [];
    _pollCycle = 0;
    _sessionId = null;
    _sessionStartedAt = null;
    _socPredictor.reset();
    _gpsSpeedKph = null;
    _elevationM = null;
    _gradePct = null;
    _prevGpsLat = null;
    _prevGpsLng = null;
    _prevElevForGrade = null;
    _gpsDistanceAccumM = 0;
    state = state.copyWith(
      stage: ObdConnectionStage.idle,
      clearSelectedDevice: true,
      statusMessage: 'Disconnected from adapter.',
      socPrediction: SocPrediction.noData(state.chargeThresholdPct),
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
    if (_isPolling) {
      _recordDiagnostic(
        'poll',
        'Previous poll is still running; skipping this tick.',
      );
      return;
    }
    _isPolling = true;
    try {
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
      final rawSnapshot = _buildSnapshot(results);

      // Merge GPS fields BEFORE analytics so trip distance uses GPS speed
      // when OBD speed PID is unavailable (common on Indian EVs).
      final nextSnapshot = rawSnapshot.copyWith(
        speedKph: rawSnapshot.speedKph ?? _gpsSpeedKph,
        gpsSpeedKph: _gpsSpeedKph,
        elevationM: _elevationM,
        gradePct: _gradePct,
      );

      final analytics = _analyticsCalculator.update(
        current: state.analytics,
        previous: _previousSnapshot,
        next: nextSnapshot,
      );

      _previousSnapshot = nextSnapshot;

      // Add SOH estimate after analytics (needs both snapshot + analytics)
      final snapshotWithSoh = nextSnapshot.copyWith(
        estimatedSohPercent: _estimateSoh(
          snapshot: nextSnapshot,
          analytics: analytics,
        ),
      );

      // Feed SOC predictor
      final soc = snapshotWithSoh.batteryPercent;
      final tripKm = analytics.tripDistanceKm;
      if (soc != null) {
        _socPredictor.addSample(socPct: soc, tripDistanceKm: tripKm);
      }
      final prediction = _socPredictor.predict(
        thresholdPct: state.chargeThresholdPct,
        currentSpeedKph: snapshotWithSoh.effectiveSpeedKph,
      );

      if (_pollCycle <= 1 || _pollCycle % 10 == 0) {
        _recordDiagnostic(
          'poll',
          'Polling succeeded with $enhancedMetricCountLabel',
        );
      }
      state = state.copyWith(
        stage: ObdConnectionStage.connected,
        telemetry: snapshotWithSoh,
        analytics: analytics,
        socPrediction: prediction,
        statusMessage:
            'Streaming live OBD telemetry from ${state.selectedDevice?.name ?? 'adapter'}.',
      );

      if (_pollCycle % _historyCheckpointFrequency == 0) {
        unawaited(_persistHistorySnapshot());
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
    } finally {
      _isPolling = false;
    }
  }

  String get enhancedMetricCountLabel {
    final count =
        _cachedEnhancedResults.where((result) => result.supported).length;
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
    _disposed = true;
    _pollingTimer?.cancel();
    _adapterSubscription?.cancel();
    _gpsSubscription?.cancel();
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
      prediction: state.socPrediction,
      chargeThresholdPct: state.chargeThresholdPct,
    );

    await ObdHistoryService().upsertCurrentUserEntry(entry);
    if (!_disposed) {
      ref.invalidate(obdHistoryEntriesProvider);
    }
  }

  void _recordDiagnostic(String phase, String message) {
    if (_disposed) return;
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
