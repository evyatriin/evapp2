# bluetooth_serial_android

## Pt-Br Versão

Plugin Flutter para **Bluetooth Clássico (Serial RFCOMM)** no **Android**.
Permite listar dispositivos pareados, buscar (scan), conectar, enviar e receber dados via porta serial (SPP) com leitura não bloqueante e gerenciamento automático de permissões.

> Desenvolvido por **Carlos Ronny de Sousa** para aplicações que necessitam de comunicação serial Bluetooth com dispositivos como HC-05/HC-06, ESP32, Arduino, impressoras térmicas e outros módulos SPP.

---

## ✨ Recursos

* ✅ Somente Android (Bluetooth Clássico / RFCOMM)
* ✅ Permissões automáticas em runtime (`ensurePermissions`)
* ✅ Lista dispositivos pareados
* ✅ Busca dispositivos próximos (scan)
* ✅ Conexão RFCOMM (UUID SPP padrão)
* ✅ Suporte a UUID customizado no `connect()`
* ✅ Timeout de leitura configurável no `connect()`
* ✅ Envio (`write`) e leitura (`read`) assíncrona (não bloqueante)
* ✅ Leitura de linha com `readLine()` e delimitador customizado
* ✅ Exemplo com loop contínuo de leitura
* ✅ Compatível com Android 8+ (API 26+)
* 🧪 Exemplo incluído em `example/`

> iOS não suportado (Bluetooth Clássico não é exposto pela API pública da Apple).

---

## 📦 Instalação

No seu `pubspec.yaml`:

```yaml
dependencies:
  bluetooth_serial_android: ^1.0.0
```

ou, durante o desenvolvimento local:

```yaml
dependencies:
  bluetooth_serial_android:
    path: ../bluetooth_serial_android
```

---

## 🔧 Requisitos e permissões

O plugin já declara no Manifest as permissões necessárias e o Android vai mesclar automaticamente com o app:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<queries>
  <intent>
    <action android:name="android.bluetooth.device.action.FOUND" />
  </intent>
</queries>
```

Em runtime, chame `FlutterBluetoothSerial.ensurePermissions()` antes de escanear ou conectar.

* Min SDK recomendado: 26+
* Target SDK: o mesmo do seu projeto Flutter
* Kotlin/Gradle: padrão do template recente do Flutter

---

## 🚀 Uso rápido

📘 Bluetooth Serial Cookbook (Versão S – mínima e prática)

1️⃣ **Permissões**  
Quando usar: Sempre ao iniciar o app.

```dart
await FlutterBluetoothSerial.ensurePermissions();
```

2️⃣ **Listar pareados**
Quando usar: Mostrar dispositivos já pareados.

```dart
final devices = await FlutterBluetoothSerial.getPairedDevices();
for (final d in devices) {
  print("${d['name']} - ${d['address']}");
}
```

3️⃣ **Scan + evento de dispositivo encontrado**
Quando usar: Descobrir dispositivos próximos.

```dart
FlutterBluetoothSerial.scanDevices().then((list) {
  print("Scan terminou, encontrados: ${list.length}");
});

FlutterBluetoothSerial.onDeviceFound.listen((d) {
  print("Encontrado: ${d['name']} - ${d['address']}");
});
```

4️⃣ **Conectar (com UUID custom e timeout)**
Quando usar: Conectar a um HC-05, ESP32, impressora, etc.

```dart
final ok = await FlutterBluetoothSerial.connect(
  "00:22:11:AA:BB:CC",
  uuid: "00001101-0000-1000-8000-00805F9B34FB",
  timeoutMs: 300,
);
print(ok ? "Conectado" : "Falhou");
```

5️⃣ **Enviar dados (write)**
Quando usar: Envio simples de comando ou texto.

```dart
await FlutterBluetoothSerial.write("LED_ON\n");
```

6️⃣ **Ler uma vez (`read()`)**
Quando usar: Leitura pontual.

```dart
final data = await FlutterBluetoothSerial.read();
print("Recebido: $data");
```

7️⃣ **Ler linha (`readLine()`) com delimitador**
Quando usar: Quando o dispositivo envia linhas concluídas.

```dart
final line = await FlutterBluetoothSerial.readLine("\n");
print("Linha: $line");
```

8️⃣ **Loop simples de leitura**
Quando usar: Para monitorar continuamente.

```dart
bool reading = true;
while (reading) {
  final data = await FlutterBluetoothSerial.read();
  if (data != null) print(">> $data");
  await Future.delayed(const Duration(milliseconds: 50));
}
```

9️⃣ **Desconectar**
Quando usar: Finalizar sessão.

```dart
await FlutterBluetoothSerial.disconnect();
print("Desconectado");

```


---

## 🛠️ API do Plugin

| Método                                                                  | Descrição                                                                                               |
|-------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `Future<bool> ensurePermissions()`                                      | Verifica e solicita permissões de Bluetooth e Localização quando necessário.                            |
| `Future<List<Map<String, String>>> getPairedDevices()`                  | Retorna uma lista de dispositivos pareados (`name`, `address`).                                         |
| `Future<List<Map<String, String>>> scanDevices()`                       | Realiza busca (scan) e retorna a lista de dispositivos encontrados.                                     |
| `Future<bool> connect(String address, {String uuid, int timeoutMs})`    | Conecta via RFCOMM/Serial. Suporta UUID customizado e timeout de leitura configurável.                  |
| `Future<void> disconnect()`                                             | Desconecta do dispositivo atual e limpa buffers.                                                        |
| `Future<void> write(String message)`                                    | Envia dados de forma assíncrona (não bloqueante).                                                       |
| `Future<String?> read()`                                                | Lê até 1024 bytes de forma assíncrona. Retorna `null` em timeout ou se não houver dados.                |
| `Future<String?> readLine([String delimiter = '\n'])`                   | Lê até receber uma linha completa (com base no delimitador). Retorna `null` em timeout.                 |


---

## 📚 Boas Práticas

* Sempre chame `ensurePermissions()` antes de fazer `scan` ou `connect()` (o plugin já tenta solicitar automaticamente, mas é recomendado chamar no início do app).
* Prefira usar leitura com delimitador (`readLine()`) quando possível — reduz necessidade de tratar buffers manualmente.
* Se usar `read()` em loop, inclua um `delay` pequeno (ex: 30–80ms) para evitar alto consumo de CPU.
* Utilize delimitadores (`\n`, `\r` ou `\r\n`) para identificar mensagens completas do dispositivo.
* Se o dispositivo usa um UUID diferente do SPP padrão, passe o UUID customizado no `connect()`.
* Ajuste o `timeoutMs` do `connect()` conforme o tempo que o dispositivo costuma demorar para responder.
* Sempre pare loops de leitura **antes** de chamar `disconnect()`.
* Use `disconnect()` para limpar buffer e fechar streams corretamente.
* Evite chamar `read()` simultaneamente em vários locais — prefira um único loop central de leitura.

---

## ❓ Perguntas frequentes

**1) Funciona no iOS?**
Não. O iOS não expõe API pública para Bluetooth Clássico.

**2) Por que pede localização?**
Exigência do Android para descoberta de dispositivos Bluetooth próximos.

**3) Preciso editar o Manifest?**
Não. O Manifest do plugin é mesclado automaticamente.

**4) A leitura captura tudo de uma vez?**
Lê até o tamanho do buffer (1024 bytes). Use delimitadores.

---

## 🧩 Exemplo de erros comuns

* **MissingPluginException**
  Verifique o nome do canal (`bluetooth_serial_android`) e rode `flutter clean`.

* **Nada aparece no scan**
  Verifique permissões e Bluetooth ativado.

* **App trava ao ler**
  Atualize o plugin. O método `read()` agora roda em thread separada.

---

## 🧠 Roadmap

### ✅ Concluído
* Suporte a UUID customizado no `connect()`
* `readLine(delimiter)` com buffer interno
* Suporte a timeout no `connect(timeoutMs)`

### 🚧 Em andamento / Planejado
* Evento nativo `onDataReceived` (stream, sem precisar de loop manual)
* Stream de status de conexão (onConnect / onDisconnect)


---

## 👨‍🎓 Autor

**Carlos Ronny de Sousa**
Professor e desenvolvedor Flutter/Android/IoT.
Foco em ensino prático e integração de hardware.

---

## 🔄 Licença

MIT License
Copyright (c) 2025 Carlos Ronny de Sousa
Consulte o arquivo [LICENSE](LICENSE) para detalhes.

