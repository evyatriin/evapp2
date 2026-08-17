import 'bluetooth_serial_android_platform_interface.dart';

/// Main API for Bluetooth Serial (RFCOMM) communication on Android.
///
/// This class provides static methods to request permissions, list
/// devices, discover new ones, connect, send, and receive data
/// via Classic Bluetooth.
class FlutterBluetoothSerial {
  /// Checks and requests the necessary permissions for using Bluetooth on Android.
  ///
  /// Returns `true` if permissions have already been granted
  /// or if the user grants them after the request.
  static Future<bool> ensurePermissions() {
    return BluetoothSerialPlatform.instance.ensurePermissions();
  }

  /// Returns the list of Bluetooth devices already paired with the phone.
  ///
  /// Each item in the list contains:
  /// * `name`: device name
  /// * `address`: MAC address
  static Future<List<Map<String, String>>> getPairedDevices() {
    return BluetoothSerialPlatform.instance.getPairedDevices();
  }

  /// Starts scanning for nearby Bluetooth devices.
  ///
  /// Each item in the list contains:
  /// * `name`: device name
  /// * `address`: MAC address
  ///
  /// Returns a final list of devices once the scan is complete.
  static Future<List<Map<String, String>>> scanDevices() {
    return BluetoothSerialPlatform.instance.scanDevices();
  }

  /// Connects to a Bluetooth device using the provided MAC address.
  ///
  /// [address] is required and must be the device's MAC Address (e.g. `00:11:22:AA:BB:CC`).
  ///
  /// [uuid] allows setting a custom UUID for devices that do not use
  /// the standard SPP. By default, it uses the UUID `00001101-0000-1000-8000-00805F9B34FB`.
  ///
  /// [timeoutMs] defines the maximum connection attempt time before throwing an error.
  ///
  /// Returns `true` if the connection is successful.
  static Future<bool> connect(
    String address, {
    String uuid = "00001101-0000-1000-8000-00805F9B34FB",
    int timeoutMs = 200,
  }) {
    return BluetoothSerialPlatform.instance.connect(
      address,
      uuid: uuid,
      timeoutMs: timeoutMs,
    );
  }

  /// Ends the current Bluetooth connection and releases resources.
  static Future<void> disconnect() {
    return BluetoothSerialPlatform.instance.disconnect();
  }

  /// Sends data to the connected Bluetooth device.
  ///
  /// Does not automatically add line breaks.
  /// If needed, include `\n`, `\r`, or `\r\n` manually.
  static Future<void> write(String message) {
    return BluetoothSerialPlatform.instance.write(message);
  }

  /// Reads data received from the Bluetooth device.
  ///
  /// Returns:
  /// * String containing the received data
  /// * `null` if no data is available or if a timeout occurs
  static Future<String?> read() {
    return BluetoothSerialPlatform.instance.read();
  }

  /// Reads a complete line based on a delimiter such as `\n`, `\r`, or `\r\n`.
  ///
  /// Useful for devices that send messages terminated by special characters.
  ///
  /// Returns:
  /// * The line without the delimiter
  /// * `null` if a timeout occurs or if the line is not yet complete
  static Future<String?> readLine([String delimiter = "\n"]) {
    return BluetoothSerialPlatform.instance.readLine(delimiter);
  }
}
