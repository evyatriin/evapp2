import 'package:flutter/services.dart';
import 'bluetooth_serial_android_platform_interface.dart';

/// Implementação do canal de comunicação via `MethodChannel`
/// entre o Flutter e o código nativo Android.
///
/// Esta classe traduz chamadas Dart para métodos Kotlin usando
/// o canal `"bluetooth_serial_android"`.
class MethodChannelBluetoothSerial extends BluetoothSerialPlatform {
  /// Canal de comunicação com o código nativo Android.
  static const _channel = MethodChannel('bluetooth_serial_android');

  /// Verifica e solicita permissões necessárias para uso do Bluetooth.
  ///
  /// Retorna `true` caso as permissões estejam ou sejam concedidas com sucesso.
  @override
  Future<bool> ensurePermissions() async {
    final result = await _channel.invokeMethod('ensurePermissions');
    return result == true;
  }

  /// Retorna a lista de dispositivos pareados com o telefone.
  ///
  /// Cada item contém:
  /// * `name` — nome do dispositivo
  /// * `address` — MAC Address
  @override
  Future<List<Map<String, String>>> getPairedDevices() async {
    final result = await _channel.invokeMethod('getPairedDevices');
    return List<Map<String, String>>.from(
      (result as List).map((e) => Map<String, String>.from(e)),
    );
  }

  /// Realiza scan por dispositivos Bluetooth próximos.
  ///
  /// Retorna uma lista final após o término da busca.
  ///
  /// Durante o scan, o plugin também pode emitir eventos `onDeviceFound`
  /// (caso implementado no código nativo).
  @override
  Future<List<Map<String, String>>> scanDevices() async {
    final result = await _channel.invokeMethod('scanDevices');
    return List<Map<String, String>>.from(
      (result as List).map((e) => Map<String, String>.from(e)),
    );
  }

  /// Conecta a um dispositivo Bluetooth usando o MAC Address informado.
  ///
  /// [address] — endereço MAC do dispositivo alvo.
  ///
  /// [uuid] — UUID do serviço RFCOMM a ser utilizado.
  /// Caso não informado, o UUID SPP padrão será usado.
  ///
  /// [timeoutMs] — tempo máximo de espera para conexão antes de gerar erro.
  ///
  /// Retorna `true` caso a conexão seja bem-sucedida.
  @override
  Future<bool> connect(
    String address, {
    String uuid = "00001101-0000-1000-8000-00805F9B34FB",
    int timeoutMs = 200,
  }) async {
    final result = await _channel.invokeMethod('connect', {
      'address': address,
      'uuid': uuid,
      'timeoutMs': timeoutMs,
    });
    return result == true;
  }

  /// Encerra a conexão Bluetooth atual, liberando recursos.
  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  /// Envia texto ao dispositivo conectado via Bluetooth.
  ///
  /// Não adiciona automaticamente delimitadores de linha.
  @override
  Future<void> write(String message) async {
    await _channel.invokeMethod('write', {'message': message});
  }

  /// Lê dados recebidos do dispositivo.
  ///
  /// Retorna:
  /// * `String` caso dados estejam disponíveis
  /// * `null` no caso de timeout ou nenhum dado
  @override
  Future<String?> read() async {
    return await _channel.invokeMethod('read');
  }

  /// Lê uma linha completa até encontrar o [delimiter].
  ///
  /// Útil quando o dispositivo envia dados separados por `\n`, `\r` ou `\r\n`.
  ///
  /// Retorna:
  /// * Linha recebida sem o delimitador
  /// * `null` no caso de timeout ou linha incompleta
  @override
  Future<String?> readLine([String delimiter = "\n"]) async {
    return await _channel.invokeMethod('readLine', {'delimiter': delimiter});
  }
}
