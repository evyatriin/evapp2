import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'bluetooth_serial_android_method_channel.dart';

abstract class BluetoothSerialPlatform extends PlatformInterface {
  BluetoothSerialPlatform() : super(token: _token);

  static final Object _token = Object();

  static BluetoothSerialPlatform _instance = MethodChannelBluetoothSerial();

  /// Implementação padrão (Android)
  static BluetoothSerialPlatform get instance => _instance;

  static set instance(BluetoothSerialPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Métodos que toda plataforma deve implementar
  Future<List<Map<String, String>>> getPairedDevices() {
    throw UnimplementedError('getPairedDevices() has not been implemented.');
  }

  Future<List<Map<String, String>>> scanDevices() {
    throw UnimplementedError('scanDevices() has not been implemented.');
  }

  Future<bool> connect(
    String address, {
    String uuid = "00001101-0000-1000-8000-00805F9B34FB",
    int timeoutMs = 200,
  });
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  Future<void> write(String message) {
    throw UnimplementedError('write() has not been implemented.');
  }

  Future<String?> read() {
    throw UnimplementedError('read() has not been implemented.');
  }

  Future<String?> readLine([String delimiter = "\n"]) {
    throw UnimplementedError('readLine() has not been implemented.');
  }

  Future<bool> ensurePermissions() {
    throw UnimplementedError('ensurePermissions() has not been implemented.');
  }
}
