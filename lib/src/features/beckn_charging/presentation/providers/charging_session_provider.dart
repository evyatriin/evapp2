import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/app_config.dart';
import '../../data/beckn_charging_service.dart';
import '../../domain/charging_session_models.dart';

class ChargingSessionNotifier extends Notifier<ChargingSession?> {
  late BecknChargingService _service;
  WebSocketChannel? _channel;
  Timer? _pollTimer;
  StreamSubscription<dynamic>? _wsSub;

  @override
  ChargingSession? build() {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    _service = BecknChargingService(accessToken: accessToken);
    ref.onDispose(_disposeResources);
    return null;
  }

  Future<void> startSession({
    required String chargerId,
    required String connectorId,
    required double rate,
    String? vehicleId,
  }) async {
    // Set starting state
    state = ChargingSession(
      sessionId: '',
      chargerId: chargerId,
      connectorId: connectorId,
      status: SessionStatus.starting,
      startTime: DateTime.now(),
    );

    try {
      final idempotencyKey = const Uuid().v4();
      final request = SessionStartRequest(
        chargerId: chargerId,
        connectorId: connectorId,
        chargingRateInrPerKwh: rate,
        vehicleId: vehicleId,
        idempotencyKey: idempotencyKey,
      );

      final sessionId = await _service.startSession(request);

      state = ChargingSession(
        sessionId: sessionId,
        chargerId: chargerId,
        connectorId: connectorId,
        status: SessionStatus.charging,
        startTime: DateTime.now(),
      );

      // Try WebSocket first, fall back to polling
      _connectWebSocket(sessionId);
    } catch (e) {
      state = ChargingSession(
        sessionId: '',
        chargerId: chargerId,
        connectorId: connectorId,
        status: SessionStatus.failed,
        startTime: DateTime.now(),
        errorMessage: e.toString(),
      );
    }
  }

  void _connectWebSocket(String sessionId) {
    try {
      final baseUrl = AppConfig.backendBaseUrl;
      // Convert https:// to wss:// (or http:// to ws://)
      final wsUrl = baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');

      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;

      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/api/chargers/ws/session/$sessionId'),
      );

      // Send auth message first
      if (accessToken != null) {
        _channel!.sink.add(
          jsonEncode(<String, dynamic>{'type': 'auth', 'token': accessToken}),
        );
      }

      _wsSub = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            if (data['type'] == 'meter_update') {
              final reading = MeterReading.fromJson(
                data['data'] as Map<String, dynamic>? ?? data,
              );
              final current = state;
              if (current != null) {
                state = current.copyWith(
                  latestReading: reading,
                  status: SessionStatus.charging,
                );
              }
            }
          } catch (_) {
            // Ignore malformed messages
          }
        },
        onError: (_) => _startPolling(sessionId),
        onDone: () {
          // If session is still charging, fall back to polling
          if (state?.status == SessionStatus.charging) {
            _startPolling(sessionId);
          }
        },
      );
    } catch (_) {
      // WebSocket unavailable — use polling
      _startPolling(sessionId);
    }
  }

  void _startPolling(String sessionId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final statusData = await _service.getSessionStatus(sessionId);
        final current = state;
        if (current == null) return;

        MeterReading? reading;
        if (statusData['latest_reading'] is Map<String, dynamic>) {
          reading = MeterReading.fromJson(
            statusData['latest_reading'] as Map<String, dynamic>,
          );
        }

        state = current.copyWith(
          latestReading: reading ?? current.latestReading,
        );
      } catch (_) {
        // Silently ignore poll failures — keep existing state
      }
    });
  }

  Future<Map<String, dynamic>> endSession() async {
    final current = state;
    if (current == null || current.sessionId.isEmpty) {
      throw Exception('No active session to end');
    }

    final sessionId = current.sessionId;
    state = current.copyWith(status: SessionStatus.stopping);

    try {
      final paymentData = await _service.endSession(sessionId);

      _pollTimer?.cancel();
      _wsSub?.cancel();
      _channel?.sink.close();

      final paymentUri =
          paymentData['payment_uri'] as String? ??
          paymentData['upi_uri'] as String?;
      final finalCost =
          (paymentData['final_cost_inr'] as num?)?.toDouble() ??
          (paymentData['total_cost'] as num?)?.toDouble();

      state = current.copyWith(
        status: SessionStatus.awaitingPayment,
        paymentUri: paymentUri,
        finalCostInr: finalCost,
      );

      return paymentData;
    } catch (e) {
      state = current.copyWith(
        status: SessionStatus.failed,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> confirmPayment(String referenceId) async {
    final current = state;
    if (current == null || current.sessionId.isEmpty) {
      throw Exception('No session to confirm payment for');
    }

    await _service.confirmPayment(
      sessionId: current.sessionId,
      referenceId: referenceId,
    );

    state = current.copyWith(status: SessionStatus.completed);
  }

  void reset() {
    _disposeResources();
    state = null;
  }

  void _disposeResources() {
    _wsSub?.cancel();
    _channel?.sink.close();
    _pollTimer?.cancel();
    _channel = null;
    _pollTimer = null;
    _wsSub = null;
  }
}

final chargingSessionProvider =
    NotifierProvider<ChargingSessionNotifier, ChargingSession?>(
      ChargingSessionNotifier.new,
    );
