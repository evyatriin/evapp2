import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend_service.dart';
import '../../core/connectivity_service.dart';
import '../authentication/auth_service.dart';

class SosService {
  static const _queueKey = 'sos_pending_queue_v1';

  final _authService = AuthService();

  // ── Send / queue ───────────────────────────────────────────────────────────

  /// Attempt to send an SOS alert.
  ///
  /// - If **online**: sends immediately, returns the created alert.
  /// - If **offline**: persists payload to local queue and returns a
  ///   [SosResult.queued] response. Call [drainPendingAlerts] when
  ///   connectivity is restored.
  Future<SosResult> sendSosAlert({
    required String userId,
    required double latitude,
    required double longitude,
    required String carModel,
    required String phoneNumber,
    String? message,
  }) async {
    final payload = {
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'car_model': carModel,
      'phone_number': phoneNumber,
      if (message != null) 'message': message,
    };

    final online = await checkConnectivityNow();

    if (!online) {
      await _enqueue(payload);
      debugPrint('[SosService] Offline — SOS queued locally');
      return SosResult.queued();
    }

    return _send(payload);
  }

  Future<SosResult> _send(Map<String, dynamic> payload) async {
    try {
      final response = await BackendService.post(
        '/api/sos/alert',
        body: payload,
        headers: {
          if (_authService.getAuthToken() case final token?) 'Authorization': 'Bearer $token',
        },
      );
      debugPrint('[SosService] SOS sent successfully');
      return SosResult.sent(response as Map<String, dynamic>);
    } catch (e) {
      // Network failed mid-request — queue it so the user isn't stranded
      debugPrint('[SosService] Send failed, queuing: $e');
      await _enqueue(payload);
      return SosResult.queued();
    }
  }

  // ── Queue management ───────────────────────────────────────────────────────

  /// Persist a pending alert payload to SharedPreferences.
  Future<void> _enqueue(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_queueKey) ?? [];
      existing.add(jsonEncode({
        ...payload,
        '_queuedAt': DateTime.now().toIso8601String(),
      }));
      await prefs.setStringList(_queueKey, existing);
    } catch (e) {
      debugPrint('[SosService] Failed to persist SOS to queue: $e');
    }
  }

  /// How many alerts are sitting in the local queue waiting to be sent.
  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? []).length;
  }

  /// Attempt to transmit all queued alerts.
  /// Called when connectivity is restored (wire this to [connectivityStreamProvider]).
  ///
  /// Returns the number of alerts successfully sent.
  Future<int> drainPendingAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];
    if (queue.isEmpty) return 0;

    final online = await checkConnectivityNow();
    if (!online) return 0;

    int sent = 0;
    final remaining = <String>[];

    for (final raw in queue) {
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        payload.remove('_queuedAt'); // internal field, not sent to backend
        final result = await _send(payload);
        if (result.wasSent) {
          sent++;
        } else {
          remaining.add(raw); // still failed — keep in queue
        }
      } catch (e) {
        remaining.add(raw);
        debugPrint('[SosService] Drain error: $e');
      }
    }

    await prefs.setStringList(_queueKey, remaining);
    debugPrint('[SosService] Drained $sent/${queue.length} queued alerts');
    return sent;
  }

  // ── Nearby alerts ──────────────────────────────────────────────────────────

  Future<List<dynamic>> getNearbyAlerts(double lat, double lng) async {
    try {
      final response = await BackendService.get(
        '/api/sos/nearby',
        queryParams: {'lat': lat.toString(), 'long': lng.toString()},
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('[SosService] Error fetching nearby alerts: $e');
      return [];
    }
  }
}

// ─── Result type ──────────────────────────────────────────────────────────────

class SosResult {
  final bool wasSent;
  final bool wasQueued;
  final Map<String, dynamic>? alertData;

  const SosResult._({
    required this.wasSent,
    required this.wasQueued,
    this.alertData,
  });

  factory SosResult.sent(Map<String, dynamic> data) =>
      SosResult._(wasSent: true, wasQueued: false, alertData: data);

  factory SosResult.queued() =>
      SosResult._(wasSent: false, wasQueued: true);

  @override
  String toString() => wasSent ? 'SosResult.sent' : 'SosResult.queued';
}
