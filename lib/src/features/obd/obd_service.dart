import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bluetooth_serial_android/bluetooth_serial_android.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'obd_models.dart';

class ObdCommandResult {
  final String key;
  final String command;
  final String rawResponse;
  final double? value;
  final bool supported;

  const ObdCommandResult({
    required this.key,
    required this.command,
    required this.rawResponse,
    required this.value,
    required this.supported,
  });
}

typedef ObdResponseParser = double? Function(String normalizedResponse);

class ObdCommandRequest {
  final String key;
  final String command;
  final ObdResponseParser parser;
  final Duration timeout;
  final String? header;

  const ObdCommandRequest({
    required this.key,
    required this.command,
    required this.parser,
    this.timeout = const Duration(seconds: 2),
    this.header,
  });
}

class ObdEnhancedProbe {
  final String key;
  final List<ObdCommandRequest> requests;

  const ObdEnhancedProbe({required this.key, required this.requests});
}

class ObdEnhancedProfile {
  final String name;
  final List<String> brandMatchers;
  final List<String> modelMatchers;
  final List<String> headers;
  final List<ObdEnhancedProbe> probes;

  const ObdEnhancedProfile({
    required this.name,
    required this.brandMatchers,
    this.modelMatchers = const [],
    required this.headers,
    required this.probes,
  });

  bool matchesVehicle(String? brand, String? model) {
    if (brand == null || brand.isEmpty) return false;
    final normalizedBrand = brand.toLowerCase();
    final brandMatch = brandMatchers.any(normalizedBrand.contains);
    if (!brandMatch) return false;
    if (modelMatchers.isEmpty) return true;
    final normalizedModel = (model ?? '').toLowerCase();
    return modelMatchers.any(normalizedModel.contains);
  }
}

class _BleSerialLayout {
  final Guid service;
  final Guid write;
  final Guid notify;

  const _BleSerialLayout({
    required this.service,
    required this.write,
    required this.notify,
  });
}

class ObdService {
  static final Guid _nordicUartService = Guid(
    '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
  );
  static final Guid _nordicUartWrite = Guid(
    '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
  );
  static final Guid _nordicUartNotify = Guid(
    '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
  );
  static final Guid _hm10Service = Guid('0000FFE0-0000-1000-8000-00805F9B34FB');
  static final Guid _hm10Characteristic = Guid(
    '0000FFE1-0000-1000-8000-00805F9B34FB',
  );
  static final Guid _vlinkService = Guid('000018F0-0000-1000-8000-00805F9B34FB');
  static final Guid _vlinkWrite = Guid('00002AF0-0000-1000-8000-00805F9B34FB');
  static final Guid _vlinkNotify = Guid('00002AF1-0000-1000-8000-00805F9B34FB');
  static final Guid _nexasService = Guid('0000FFF0-0000-1000-8000-00805F9B34FB');
  static final Guid _nexasWrite = Guid('0000FFF1-0000-1000-8000-00805F9B34FB');
  static final Guid _nexasNotify = Guid('0000FFF2-0000-1000-8000-00805F9B34FB');
  static final Guid _microchipService = Guid(
    '49535343-FE7D-4AE5-8FA9-9FAFD205E455',
  );
  static final Guid _microchipNotify = Guid(
    '49535343-1E4D-4BD9-BA61-23C647249616',
  );
  static final Guid _microchipWrite = Guid(
    '49535343-8841-43F4-A8D4-ECBE34729BB3',
  );
  static final Guid _tioService = Guid('0000FEFB-0000-1000-8000-00805F9B34FB');
  static final Guid _tioWrite = Guid('00000001-0000-1000-8000-008025000000');
  static final Guid _tioNotify = Guid('00000002-0000-1000-8000-008025000000');
  static final List<_BleSerialLayout> _bleSerialLayouts = [
    _BleSerialLayout(
      service: _nordicUartService,
      write: _nordicUartWrite,
      notify: _nordicUartNotify,
    ),
    _BleSerialLayout(
      service: _hm10Service,
      write: _hm10Characteristic,
      notify: _hm10Characteristic,
    ),
    _BleSerialLayout(
      service: _vlinkService,
      write: _vlinkWrite,
      notify: _vlinkNotify,
    ),
    _BleSerialLayout(
      service: _nexasService,
      write: _nexasWrite,
      notify: _nexasNotify,
    ),
    _BleSerialLayout(
      service: _microchipService,
      write: _microchipWrite,
      notify: _microchipNotify,
    ),
    _BleSerialLayout(
      service: _tioService,
      write: _tioWrite,
      notify: _tioNotify,
    ),
  ];
  static const String _serialPortProfileUuid =
      '00001101-0000-1000-8000-00805F9B34FB';
  static const List<String> _commonEvHeaders = ['7E4', '7E2', '7E7'];
  static final List<ObdEnhancedProfile> _enhancedProfiles = [
    ObdEnhancedProfile(
      name: 'Tata EV Battery UDS',
      brandMatchers: ['tata'],
      headers: ['7E4', '7E2', '7E7'],
      probes: _buildCommonEnhancedProbes(['7E4', '7E2', '7E7']),
    ),
    ObdEnhancedProfile(
      name: 'MG EV Battery UDS',
      brandMatchers: ['mg'],
      headers: ['7E2', '7E4', '7E7'],
      probes: _buildCommonEnhancedProbes(['7E2', '7E4', '7E7']),
    ),
    ObdEnhancedProfile(
      name: 'Hyundai/Kia EV Battery UDS',
      brandMatchers: ['hyundai', 'kia'],
      headers: ['7E4', '7E7', '7E2'],
      probes: _buildCommonEnhancedProbes(['7E4', '7E7', '7E2']),
    ),
    ObdEnhancedProfile(
      name: 'Mahindra EV Battery UDS',
      brandMatchers: ['mahindra'],
      headers: ['7E2', '7E7', '7E4'],
      probes: _buildCommonEnhancedProbes(['7E2', '7E7', '7E4']),
    ),
    ObdEnhancedProfile(
      name: 'BYD EV Battery UDS',
      brandMatchers: ['byd'],
      headers: ['7E7', '7E4', '7E2'],
      probes: _buildCommonEnhancedProbes(['7E7', '7E4', '7E2']),
    ),
    ObdEnhancedProfile(
      name: 'Nissan Leaf Battery UDS',
      brandMatchers: ['nissan'],
      modelMatchers: ['leaf'],
      headers: ['7E2', '7E4', '7E7'],
      probes: _buildCommonEnhancedProbes(['7E2', '7E4', '7E7']),
    ),
    ObdEnhancedProfile(
      name: 'Experimental EV Battery UDS',
      brandMatchers: [
        'tata',
        'mg',
        'mahindra',
        'hyundai',
        'kia',
        'byd',
        'nissan',
      ],
      headers: _commonEvHeaders,
      probes: _buildCommonEnhancedProbes(_commonEvHeaders),
    ),
  ];

  final Map<String, BluetoothDevice> _knownBleDevices = {};
  final Map<String, ObdScanDevice> _classicDevices = {};

  BluetoothDevice? _bleDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  ObdTransport? _activeTransport;
  Completer<String>? _pendingResponse;
  final StringBuffer _responseBuffer = StringBuffer();
  String? _activeHeader;

  late void Function(List<ObdScanDevice>) _onScanResults;
  late void Function(bool) _onScanningChanged;
  void Function(String phase, String message)? _onDiagnosticEvent;

  void bindDiagnostics(
    void Function(String phase, String message) onDiagnosticEvent,
  ) {
    _onDiagnosticEvent = onDiagnosticEvent;
  }

  void _emitDiagnostic(String phase, String message) {
    _onDiagnosticEvent?.call(phase, message);
  }

  static List<ObdEnhancedProbe> _buildCommonEnhancedProbes(
    List<String> headers,
  ) {
    List<ObdCommandRequest> buildRequests(
      String key,
      String command,
      ObdResponseParser parser,
    ) {
      return [
        for (final header in headers)
          ObdCommandRequest(
            key: key,
            command: command,
            header: header,
            timeout: const Duration(seconds: 3),
            parser: parser,
          ),
      ];
    }

    return [
      ObdEnhancedProbe(
        key: 'batteryPercent',
        requests: buildRequests(
          'batteryPercent',
          '220101',
          _parseExperimentalPercent,
        ),
      ),
      ObdEnhancedProbe(
        key: 'batteryPackVoltage',
        requests: buildRequests(
          'batteryPackVoltage',
          '220102',
          _parseExperimentalVoltage,
        ),
      ),
      ObdEnhancedProbe(
        key: 'batteryCurrent',
        requests: buildRequests(
          'batteryCurrent',
          '220103',
          _parseExperimentalCurrent,
        ),
      ),
      ObdEnhancedProbe(
        key: 'batteryTempC',
        requests: buildRequests(
          'batteryTempC',
          '220104',
          _parseExperimentalTemperature,
        ),
      ),
      ObdEnhancedProbe(
        key: 'stateOfHealth',
        requests: buildRequests(
          'stateOfHealth',
          '220105',
          _parseExperimentalPercent,
        ),
      ),
      ObdEnhancedProbe(
        key: 'cellDeltaMv',
        requests: buildRequests(
          'cellDeltaMv',
          '220106',
          _parseExperimentalCellDelta,
        ),
      ),
    ];
  }

  void bindScanStreams({
    required void Function(List<ObdScanDevice>) onScanResults,
    required void Function(bool) onScanningChanged,
  }) {
    _onScanResults = onScanResults;
    _onScanningChanged = onScanningChanged;

    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        _knownBleDevices[result.device.remoteId.str] = result.device;
      }

      _emitScanResults(_mapBleScanResults(results));
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      _onScanningChanged(isScanning);
      if (!isScanning && Platform.isAndroid) {
        unawaited(_safeRefreshClassicDevices());
      }
    });
  }

  Future<void> _safeRefreshClassicDevices() async {
    try {
      await _refreshClassicDevices();
    } catch (_) {
      // Some Android builds block classic discovery even while BLE scanning works.
    }
  }

  Future<ObdTransportSupport> ensurePermissions() async {
    final permissions = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetoothConnect,
      if (Platform.isAndroid) Permission.bluetoothScan,
    ];

    final statuses = await permissions.request();
    final runtimePermissionsGranted = statuses.values.every(
      (status) => status.isGranted || status.isLimited || status.isRestricted,
    );

    final classicSupported = Platform.isAndroid;
    final bleSupported = await FlutterBluePlus.isSupported;
    final classicPermissionsGranted =
        classicSupported
            ? await FlutterBluetoothSerial.ensurePermissions()
            : false;

    return ObdTransportSupport(
      bleSupported: bleSupported,
      blePermissionsGranted: runtimePermissionsGranted,
      classicSupported: classicSupported,
      classicPermissionsGranted:
          runtimePermissionsGranted &&
          (!classicSupported || classicPermissionsGranted),
    );
  }

  Future<List<ObdScanDevice>> startScan() async {
    _emitDiagnostic('scan', 'Starting BLE and classic Bluetooth scan.');
    final bleDevices = await _startBleScan();
    List<ObdScanDevice> classicDevices = const [];
    if (Platform.isAndroid) {
      try {
        classicDevices = await _refreshClassicDevices(includeDiscovery: true);
      } catch (_) {
        classicDevices = const [];
      }
    }
    return _emitScanResults([...bleDevices, ...classicDevices]);
  }

  Future<void> stopScan() async {
    _emitDiagnostic('scan', 'Stopping active scan.');
    await FlutterBluePlus.stopScan();
  }

  Future<void> connect(ObdScanDevice device) async {
    _activeTransport = device.transport;
    _emitDiagnostic(
      'connect',
      'Opening ${device.transportLabel} link to ${device.name}.',
    );

    if (device.transport == ObdTransport.classicBluetooth) {
      await _connectClassic(device);
      return;
    }

    await _connectBle(device);
  }

  Future<void> disconnect() async {
    _emitDiagnostic('connect', 'Disconnecting from adapter.');
    _pendingResponse?.completeError(
      StateError('Disconnected before the adapter replied.'),
    );
    _pendingResponse = null;
    _responseBuffer.clear();

    await _valueSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _valueSubscription = null;
    _connectionSubscription = null;

    if (_bleDevice != null && _bleDevice!.isConnected) {
      await _bleDevice!.disconnect();
    }

    if (_activeTransport == ObdTransport.classicBluetooth) {
      await FlutterBluetoothSerial.disconnect();
    }

    _bleDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _activeTransport = null;
  }

  Future<List<ObdCommandResult>> pollStandardTelemetry() async {
    _emitDiagnostic('poll', 'Polling standard OBD-II telemetry.');
    final requests = <ObdCommandRequest>[
      ObdCommandRequest(
        key: 'speedKph',
        command: '010D',
        parser:
            (response) => _parsePidValue(
              response,
              '010D',
              (bytes) => bytes[0].toDouble(),
            ),
      ),
      ObdCommandRequest(
        key: 'rpm',
        command: '010C',
        parser:
            (response) => _parsePidValue(
              response,
              '010C',
              (bytes) => ((bytes[0] * 256) + bytes[1]) / 4,
            ),
      ),
      ObdCommandRequest(
        key: 'throttlePercent',
        command: '0111',
        parser:
            (response) => _parsePidValue(
              response,
              '0111',
              (bytes) => bytes[0] * 100 / 255,
            ),
      ),
      ObdCommandRequest(
        key: 'engineLoadPercent',
        command: '0104',
        parser:
            (response) => _parsePidValue(
              response,
              '0104',
              (bytes) => bytes[0] * 100 / 255,
            ),
      ),
      ObdCommandRequest(
        key: 'coolantTempC',
        command: '0105',
        parser:
            (response) =>
                _parsePidValue(response, '0105', (bytes) => bytes[0] - 40),
      ),
      ObdCommandRequest(
        key: 'intakeTempC',
        command: '010F',
        parser:
            (response) =>
                _parsePidValue(response, '010F', (bytes) => bytes[0] - 40),
      ),
      ObdCommandRequest(
        key: 'controlModuleVoltage',
        command: '0142',
        parser:
            (response) => _parsePidValue(
              response,
              '0142',
              (bytes) => ((bytes[0] * 256) + bytes[1]) / 1000,
            ),
      ),
      ObdCommandRequest(
        key: 'batteryPercent',
        command: '015B',
        parser:
            (response) => _parsePidValue(
              response,
              '015B',
              (bytes) => bytes[0] * 100 / 255,
            ),
      ),
      ObdCommandRequest(
        key: 'controlModuleVoltage',
        command: 'ATRV',
        parser: _parseVoltageString,
      ),
    ];

    final results = <ObdCommandResult>[];
    for (final request in requests) {
      try {
        results.add(await _executeRequest(request));
      } catch (_) {
        results.add(
          ObdCommandResult(
            key: request.key,
            command: request.command,
            rawResponse: '',
            value: null,
            supported: false,
          ),
        );
      }
    }
    return results;
  }

  Future<List<ObdCommandResult>> pollEnhancedTelemetry({
    String? vehicleBrand,
    String? vehicleModel,
  }) async {
    final profile = _resolveEnhancedProfile(
      vehicleBrand: vehicleBrand,
      vehicleModel: vehicleModel,
    );
    if (profile == null) {
      _emitDiagnostic(
        'profile',
        'No enhanced EV battery profile matched this vehicle.',
      );
      return const [];
    }
    _emitDiagnostic('profile', 'Using enhanced profile ${profile.name}.');

    final results = <ObdCommandResult>[];
    for (final probe in profile.probes) {
      results.add(await _resolveEnhancedProbe(probe));
    }
    await _applyDefaultHeader();
    return results;
  }

  ObdEnhancedProfile? resolveEnhancedProfile({
    String? vehicleBrand,
    String? vehicleModel,
  }) {
    return _resolveEnhancedProfile(
      vehicleBrand: vehicleBrand,
      vehicleModel: vehicleModel,
    );
  }

  ObdEnhancedProfile? _resolveEnhancedProfile({
    String? vehicleBrand,
    String? vehicleModel,
  }) {
    for (final profile in _enhancedProfiles) {
      if (profile.matchesVehicle(vehicleBrand, vehicleModel)) {
        return profile;
      }
    }
    return null;
  }

  Future<ObdCommandResult> _resolveEnhancedProbe(ObdEnhancedProbe probe) async {
    for (final request in probe.requests) {
      try {
        final result = await _executeRequest(request);
        if (result.supported && result.value != null) {
          return result;
        }
      } catch (_) {
        continue;
      }
    }

    return ObdCommandResult(
      key: probe.key,
      command: probe.requests.first.command,
      rawResponse: '',
      value: null,
      supported: false,
    );
  }

  Future<String?> fetchVin() async {
    try {
      final response = await _sendCommand(
        '0902',
        timeout: const Duration(seconds: 3),
      );
      final cleaned = _normalizeResponse(response);
      if (cleaned.isEmpty) return null;
      return _parseVin(cleaned);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    unawaited(disconnect());
  }

  Future<List<ObdScanDevice>> _startBleScan() async {
    if (!await FlutterBluePlus.isSupported) {
      _emitDiagnostic('scan', 'BLE is not supported on this phone.');
      return const [];
    }

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 12),
      webOptionalServices: [
        for (final layout in _bleSerialLayouts) layout.service,
      ],
    );

    final existingResults = FlutterBluePlus.lastScanResults;
    return _mapBleScanResults(existingResults);
  }

  List<ObdScanDevice> _mapBleScanResults(List<ScanResult> results) {
    return results
        .map(ObdScanDevice.fromScanResult)
        .where((device) {
          final name = device.name.toLowerCase();
          final looksLikeObd =
              name.contains('obd') ||
              name.contains('elm') ||
              name.contains('vlink') ||
              name.contains('icar') ||
              name.contains('vgate') ||
              name.contains('kw') ||
              name.contains('can') ||
              name.contains('scanner') ||
              name.contains('diag') ||
              name.contains('diagnostic');

          // Many adapters advertise with generic or short names. Prefer
          // showing anything connectable instead of hiding valid adapters.
          return looksLikeObd || device.isConnectable;
        })
        .fold<Map<String, ObdScanDevice>>({}, (map, device) {
          map[device.id] = device;
          return map;
        })
        .values
        .toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  Future<List<ObdScanDevice>> _refreshClassicDevices({
    bool includeDiscovery = false,
  }) async {
    if (!Platform.isAndroid) {
      return const [];
    }

    final nextDevices = <String, ObdScanDevice>{};

    for (final device in await FlutterBluetoothSerial.getPairedDevices()) {
      final mapped = _mapClassicDevice(device);
      if (mapped != null) {
        nextDevices[mapped.id] = mapped;
      }
    }

    if (includeDiscovery) {
      _emitDiagnostic(
        'scan',
        'Refreshing paired and discovered classic Bluetooth devices.',
      );
      for (final device in await FlutterBluetoothSerial.scanDevices()) {
        final mapped = _mapClassicDevice(device);
        if (mapped != null) {
          nextDevices[mapped.id] = mapped;
        }
      }
    }

    _classicDevices
      ..clear()
      ..addAll(nextDevices);

    return _emitScanResults([
      ..._mapBleScanResults(FlutterBluePlus.lastScanResults),
      ..._classicDevices.values,
    ]);
  }

  ObdScanDevice? _mapClassicDevice(Map<String, String> device) {
    final address = device['address']?.trim();
    if (address == null || address.isEmpty) {
      return null;
    }

    final name =
        (device['name']?.trim().isNotEmpty ?? false)
            ? device['name']!.trim()
            : 'Classic OBD Adapter';

    return ObdScanDevice.classic(address: address, name: name);
  }

  List<ObdScanDevice> _emitScanResults(List<ObdScanDevice> devices) {
    final merged =
        {for (final device in devices) device.id: device}.values.toList()
          ..sort((a, b) {
            if (a.transport != b.transport) {
              return a.transport.index.compareTo(b.transport.index);
            }
            return b.rssi.compareTo(a.rssi);
          });

    _onScanResults(merged);
    return merged;
  }

  Future<void> _connectBle(ObdScanDevice device) async {
    final bleDevice =
        _knownBleDevices[device.id] ?? BluetoothDevice.fromId(device.id);
    _bleDevice = bleDevice;

    await stopScan();
    _emitDiagnostic('connect', 'Connecting over BLE.');
    await bleDevice.connect(
      license: License.free,
      mtu: 256,
      timeout: const Duration(seconds: 20),
    );
    try {
      await bleDevice.requestMtu(185);
    } catch (_) {
      // Some adapters reject MTU changes after the initial connect.
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));

    _connectionSubscription?.cancel();
    _connectionSubscription = bleDevice.connectionState.listen((_) {});
    bleDevice.cancelWhenDisconnected(_connectionSubscription!, delayed: true);

    final services = await bleDevice.discoverServices();
    _emitDiagnostic(
      'ble',
      'Discovered ${services.length} BLE services on the adapter.',
    );
    _resolveBleTransport(services);

    if (_writeCharacteristic == null || _notifyCharacteristic == null) {
      _emitDiagnostic(
        'ble',
        'No compatible BLE UART service was found after discovery.',
      );
      throw StateError(
        'Connected, but no compatible BLE UART service was found on this adapter.',
      );
    }

    await _notifyCharacteristic!.setNotifyValue(true);
    _valueSubscription?.cancel();
    _valueSubscription = _notifyCharacteristic!.onValueReceived.listen(
      _handleValue,
    );
    bleDevice.cancelWhenDisconnected(_valueSubscription!, delayed: true);

    await _initializeElm327();
  }

  Future<void> _connectClassic(ObdScanDevice device) async {
    await stopScan();
    var connected = false;
    final address = device.macAddress ?? device.id;
    for (final timeout in const [3500, 8000]) {
      _emitDiagnostic(
        'classic',
        'Trying classic Bluetooth connection with ${timeout}ms timeout.',
      );
      connected = await FlutterBluetoothSerial.connect(
        address,
        uuid: _serialPortProfileUuid,
        timeoutMs: timeout,
      );
      if (connected) {
        break;
      }
    }
    if (!connected) {
      _emitDiagnostic('classic', 'Classic Bluetooth connection failed.');
      throw StateError('Classic Bluetooth connection failed.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
    _emitDiagnostic('classic', 'Classic Bluetooth link established.');

    await _initializeElm327();
  }

  void _resolveBleTransport(List<BluetoothService> services) {
    BluetoothCharacteristic? writeCharacteristic;
    BluetoothCharacteristic? notifyCharacteristic;

    for (final layout in _bleSerialLayouts) {
      final service = services.cast<BluetoothService?>().firstWhere(
        (candidate) => candidate?.uuid == layout.service,
        orElse: () => null,
      );
      if (service == null) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid == layout.write) {
          writeCharacteristic = characteristic;
        }
        if (characteristic.uuid == layout.notify) {
          notifyCharacteristic = characteristic;
        }
      }
      if (writeCharacteristic != null && notifyCharacteristic != null) {
        _emitDiagnostic(
          'ble',
          'Matched BLE UART layout ${layout.service.str}.',
        );
        _writeCharacteristic = writeCharacteristic;
        _notifyCharacteristic = notifyCharacteristic;
        return;
      }
    }

    for (final service in services) {
      if (service.uuid == _hm10Service) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == _hm10Characteristic) {
            if (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse) {
              writeCharacteristic ??= characteristic;
            }
            if (characteristic.properties.notify ||
                characteristic.properties.indicate) {
              notifyCharacteristic ??= characteristic;
            }
          }
        }
      }
    }

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (writeCharacteristic == null &&
            (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse)) {
          writeCharacteristic = characteristic;
        }
        if (notifyCharacteristic == null &&
            (characteristic.properties.notify ||
                characteristic.properties.indicate)) {
          notifyCharacteristic = characteristic;
        }
      }
    }

    _writeCharacteristic = writeCharacteristic;
    _notifyCharacteristic = notifyCharacteristic;
  }

  Future<void> _initializeElm327() async {
    _emitDiagnostic('elm', 'Initializing ELM327 adapter.');
    try {
      await _sendCommand('ATZ', timeout: const Duration(seconds: 3));
    } catch (_) {
      _emitDiagnostic('elm', 'ATZ failed, trying warm start ATWS.');
      await _sendCommand('ATWS', timeout: const Duration(seconds: 2));
    }

    for (final command in const [
      'ATE0',
      'ATL0',
      'ATS0',
      'ATH0',
      'ATAT2',
      'ATCAF0',
      'ATAL',
      'ATSP0',
    ]) {
      try {
        await _sendCommand(command);
      } catch (_) {
        _emitDiagnostic('elm', 'Adapter ignored optional init command $command.');
        // Cheap adapters vary a lot; keep going when a tuning command is ignored.
      }
    }
    await _applyDefaultHeader();
    _emitDiagnostic('elm', 'ELM327 initialization completed.');
  }

  Future<ObdCommandResult> _executeRequest(ObdCommandRequest request) async {
    if (request.header != null) {
      await _setHeader(request.header!);
    } else {
      await _applyDefaultHeader();
    }

    final response = await _sendCommand(
      request.command,
      timeout: request.timeout,
    );
    final normalized = _normalizeResponse(response);
    if (normalized.isEmpty ||
        normalized.contains('NO DATA') ||
        normalized.contains('ERROR')) {
      _emitDiagnostic(
        'command',
        '${request.command} returned ${normalized.isEmpty ? 'empty response' : normalized}.',
      );
      return ObdCommandResult(
        key: request.key,
        command: request.command,
        rawResponse: normalized,
        value: null,
        supported: false,
      );
    }

    final value = request.parser(normalized);

    return ObdCommandResult(
      key: request.key,
      command: request.command,
      rawResponse: normalized,
      value: value,
      supported: value != null,
    );
  }

  Future<void> _applyDefaultHeader() async {
    await _setHeader('7DF');
  }

  Future<void> _setHeader(String header) async {
    if (_activeHeader == header) return;
    _emitDiagnostic('elm', 'Switching CAN header to $header.');
    await _sendCommand('ATSH$header', timeout: const Duration(seconds: 1));
    _activeHeader = header;
  }

  double? _parsePidValue(
    String response,
    String command,
    double Function(List<int> bytes) parser,
  ) {
    final pid = command.substring(2);
    final match = RegExp(
      '41\\s*$pid\\s*([0-9A-F ]+)',
      caseSensitive: false,
    ).firstMatch(response);
    if (match == null) return null;

    final bytes =
        match
            .group(1)!
            .trim()
            .split(RegExp(r'\s+'))
            .where((value) => value.isNotEmpty)
            .map((value) => int.tryParse(value, radix: 16))
            .whereType<int>()
            .toList();

    if (bytes.isEmpty) return null;
    return parser(bytes);
  }

  double? _parseVoltageString(String response) {
    final match = RegExp(
      r'([0-9]+(?:\.[0-9]+)?)\s*V',
      caseSensitive: false,
    ).firstMatch(response);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  Future<String> _sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _pendingResponse?.completeError(
      StateError('A new command was sent before the previous one completed.'),
    );
    _pendingResponse = Completer<String>();
    _responseBuffer.clear();

    if (_activeTransport == ObdTransport.classicBluetooth) {
      await FlutterBluetoothSerial.write('$command\r');
      final response = await _readClassicResponse(timeout, command);
      _pendingResponse = null;
      return response;
    }

    final characteristic = _writeCharacteristic;
    if (characteristic == null) {
      throw StateError('No writable characteristic available.');
    }

    final bytes = ascii.encode('$command\r');
    await characteristic.write(
      bytes,
      withoutResponse: characteristic.properties.writeWithoutResponse,
    );

    final response = await _pendingResponse!.future.timeout(
      timeout,
      onTimeout: () {
        _emitDiagnostic(
          'command',
          '$command timed out waiting for adapter response over BLE.',
        );
        throw TimeoutException(
          'BLE adapter timed out while waiting for $command.',
        );
      },
    );
    _pendingResponse = null;
    return response;
  }

  Future<String> _readClassicResponse(Duration timeout, String command) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final chunk = await FlutterBluetoothSerial.read();
      if (chunk != null && chunk.isNotEmpty) {
        _responseBuffer.write(chunk);
        if (_responseBuffer.toString().contains('>')) {
          return _responseBuffer.toString();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    _emitDiagnostic(
      'command',
      '$command timed out waiting for adapter response over classic Bluetooth.',
    );
    throw TimeoutException('Classic Bluetooth adapter timed out.');
  }

  void _handleValue(List<int> bytes) {
    final chunk = ascii.decode(bytes, allowInvalid: true);
    _responseBuffer.write(chunk);
    if (_pendingResponse != null && _responseBuffer.toString().contains('>')) {
      _pendingResponse!.complete(_responseBuffer.toString());
    }
  }

  String _normalizeResponse(String response) {
    return response
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              line != '>' &&
              line != 'OK' &&
              line != '?' &&
              !line.startsWith('AT'),
        )
        .join(' ')
        .replaceAll('SEARCHING...', '')
        .replaceAll('STOPPED', '')
        .trim()
        .toUpperCase();
  }

  static double? _parseExperimentalPercent(String response) {
    final bytes = _extractDiagnosticBytes(response);
    final candidates = <double>[
      if (bytes.isNotEmpty) bytes.first.toDouble(),
      if (bytes.length >= 2) _toUnsigned(bytes[0], bytes[1]) / 10,
      if (bytes.isNotEmpty) bytes.first * 100 / 255,
    ];
    for (final candidate in candidates) {
      if (candidate >= 0 && candidate <= 100) {
        return candidate;
      }
    }
    return null;
  }

  static double? _parseExperimentalVoltage(String response) {
    final bytes = _extractDiagnosticBytes(response);
    final candidates = <double>[
      if (bytes.length >= 2) _toUnsigned(bytes[0], bytes[1]) / 10,
      if (bytes.length >= 2) _toUnsigned(bytes[0], bytes[1]) / 100,
      if (bytes.length >= 3)
        ((bytes[0] * 65536) + (bytes[1] * 256) + bytes[2]) / 100,
    ];
    for (final candidate in candidates) {
      if (candidate >= 150 && candidate <= 1000) {
        return candidate;
      }
    }
    return null;
  }

  static double? _parseExperimentalCurrent(String response) {
    final bytes = _extractDiagnosticBytes(response);
    final candidates = <double>[
      if (bytes.length >= 2) _toSigned(bytes[0], bytes[1]) / 10,
      if (bytes.length >= 2) _toSigned(bytes[0], bytes[1]) / 100,
    ];
    for (final candidate in candidates) {
      if (candidate >= -600 && candidate <= 600) {
        return candidate;
      }
    }
    return null;
  }

  static double? _parseExperimentalTemperature(String response) {
    final bytes = _extractDiagnosticBytes(response);
    final candidates = <double>[
      if (bytes.isNotEmpty) bytes.first - 40,
      if (bytes.length >= 2) _toSigned(bytes[0], bytes[1]) / 10,
    ];
    for (final candidate in candidates) {
      if (candidate >= -40 && candidate <= 120) {
        return candidate;
      }
    }
    return null;
  }

  static double? _parseExperimentalCellDelta(String response) {
    final bytes = _extractDiagnosticBytes(response);
    final candidates = <double>[
      if (bytes.isNotEmpty) bytes.first.toDouble(),
      if (bytes.length >= 2) _toUnsigned(bytes[0], bytes[1]).toDouble(),
    ];
    for (final candidate in candidates) {
      if (candidate >= 0 && candidate <= 500) {
        return candidate;
      }
    }
    return null;
  }

  static List<int> _extractDiagnosticBytes(String response) {
    final tokens =
        response
            .split(RegExp(r'\s+'))
            .where((token) => RegExp(r'^[0-9A-F]{2}$').hasMatch(token))
            .toList();
    final bytes =
        tokens
            .map((token) => int.tryParse(token, radix: 16))
            .whereType<int>()
            .toList();
    if (bytes.length >= 3 && bytes.first == 0x62) {
      return bytes.sublist(3);
    }
    if (bytes.length >= 2 && bytes.first == 0x41) {
      return bytes.sublist(2);
    }
    return bytes;
  }

  static String? _parseVin(String response) {
    final tokens =
        response
            .split(RegExp(r'\s+'))
            .where((token) => RegExp(r'^[0-9A-F]{2}$').hasMatch(token))
            .toList();
    if (tokens.isEmpty) {
      return null;
    }

    final vinBytes = <int>[];
    for (var i = 0; i <= tokens.length - 3; i++) {
      if (tokens[i] == '49' && tokens[i + 1] == '02') {
        i += 2;
        while (i + 1 < tokens.length &&
            !(tokens[i] == '49' && tokens[i + 1] == '02')) {
          final value = int.tryParse(tokens[i], radix: 16);
          if (value != null && value >= 32 && value <= 126) {
            vinBytes.add(value);
          }
          i++;
        }
        i--;
      }
    }

    if (vinBytes.isEmpty) {
      return null;
    }

    final vin = ascii.decode(vinBytes, allowInvalid: true).trim();
    return vin.isEmpty ? null : vin;
  }

  static int _toUnsigned(int high, int low) => (high * 256) + low;

  static int _toSigned(int high, int low) {
    final value = _toUnsigned(high, low);
    return value >= 0x8000 ? value - 0x10000 : value;
  }
}

class ObdTransportSupport {
  final bool bleSupported;
  final bool blePermissionsGranted;
  final bool classicSupported;
  final bool classicPermissionsGranted;

  const ObdTransportSupport({
    required this.bleSupported,
    required this.blePermissionsGranted,
    required this.classicSupported,
    required this.classicPermissionsGranted,
  });

  bool get anySupported => bleSupported || classicSupported;
  bool get permissionsGranted =>
      blePermissionsGranted || classicPermissionsGranted;
}

class DriverAnalyticsCalculator {
  const DriverAnalyticsCalculator();

  DriverAnalytics update({
    required DriverAnalytics current,
    required ObdTelemetrySnapshot previous,
    required ObdTelemetrySnapshot next,
  }) {
    final previousSpeed = previous.speedKph ?? 0;
    final nextSpeed = next.speedKph ?? previousSpeed;
    final deltaSeconds = math.max(
      1,
      next.timestamp.difference(previous.timestamp).inSeconds,
    );

    final deltaMps = (nextSpeed - previousSpeed) / 3.6;
    final acceleration = deltaMps / deltaSeconds;
    final harshAccelerationEvents =
        current.harshAccelerationEvents + (acceleration >= 2.8 ? 1 : 0);
    final harshBrakingEvents =
        current.harshBrakingEvents + (acceleration <= -3.2 ? 1 : 0);

    final distanceIncrementKm =
        ((previousSpeed + nextSpeed) / 2) *
        (deltaSeconds / Duration.secondsPerHour);
    final tripDistanceKm = current.tripDistanceKm + distanceIncrementKm;
    final averageSpeed =
        tripDistanceKm <= 0
            ? nextSpeed
            : ((current.averageSpeedKph *
                        math.max(tripDistanceKm - distanceIncrementKm, 0)) +
                    nextSpeed * distanceIncrementKm) /
                tripDistanceKm;

    final peakSpeed = math.max(current.peakSpeedKph, nextSpeed);
    final idleTime =
        (nextSpeed < 3 && (next.rpm ?? 0) > 600)
            ? current.idleTime + Duration(seconds: deltaSeconds)
            : current.idleTime;

    final throttlePenalty = ((next.throttlePercent ?? 0) / 100) * 18;
    final harshPenalty = (harshAccelerationEvents + harshBrakingEvents) * 3.5;
    final idlePenalty = idleTime.inMinutes * 0.7;
    final efficiencyScore = (100 - throttlePenalty - harshPenalty - idlePenalty)
        .clamp(35, 100);
    final smoothDrivingScore = (100 - harshPenalty - idlePenalty * 0.4).clamp(
      30,
      100,
    );

    return DriverAnalytics(
      smoothDrivingScore: smoothDrivingScore.toDouble(),
      efficiencyScore: efficiencyScore.toDouble(),
      harshAccelerationEvents: harshAccelerationEvents,
      harshBrakingEvents: harshBrakingEvents,
      averageSpeedKph: averageSpeed,
      peakSpeedKph: peakSpeed,
      tripDistanceKm: tripDistanceKm,
      idleTime: idleTime,
    );
  }
}
