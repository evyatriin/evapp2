import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'obd_models.dart';

final obdHistoryEntriesProvider =
    FutureProvider<List<ObdHistoryEntry>>((ref) async {
      return ObdHistoryService().loadCurrentUserHistory();
    });

class ObdHistoryEntry {
  final String sessionId;
  final String userId;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String? deviceName;
  final String? deviceId;
  final double? batteryPercent;
  final double? sohPercent;
  final double? voltage;
  final double? batteryPowerKw;
  final double? temperatureC;
  final double? batteryCurrentA;
  final double? cellDeltaMv;
  final String? evProfileName;
  final double averageSpeedKph;
  final double peakSpeedKph;
  final double tripDistanceKm;
  final double smoothDrivingScore;
  final double efficiencyScore;
  final int harshEvents;
  final double? elevationM;
  final double? gradePct;
  final double? chargeThresholdPct;
  final double? predictionRemainingKm;
  final double? predictionRatePerKm;

  const ObdHistoryEntry({
    required this.sessionId,
    required this.userId,
    required this.startedAt,
    required this.updatedAt,
    required this.averageSpeedKph,
    required this.peakSpeedKph,
    required this.tripDistanceKm,
    required this.smoothDrivingScore,
    required this.efficiencyScore,
    required this.harshEvents,
    this.deviceName,
    this.deviceId,
    this.batteryPercent,
    this.sohPercent,
    this.voltage,
    this.batteryPowerKw,
    this.temperatureC,
    this.batteryCurrentA,
    this.cellDeltaMv,
    this.evProfileName,
    this.elevationM,
    this.gradePct,
    this.chargeThresholdPct,
    this.predictionRemainingKm,
    this.predictionRatePerKm,
  });

  factory ObdHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ObdHistoryEntry(
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      updatedAt: DateTime.parse(
        (json['session_updated_at'] ?? json['updated_at']) as String,
      ),
      deviceName: json['device_name'] as String?,
      deviceId: json['device_id'] as String?,
      batteryPercent: (json['battery_percent'] as num?)?.toDouble(),
      sohPercent: (json['soh_percent'] as num?)?.toDouble(),
      voltage: (json['voltage'] as num?)?.toDouble(),
      batteryPowerKw: (json['battery_power_kw'] as num?)?.toDouble(),
      temperatureC: (json['temperature_c'] as num?)?.toDouble(),
      batteryCurrentA: (json['battery_current_a'] as num?)?.toDouble(),
      cellDeltaMv: (json['cell_delta_mv'] as num?)?.toDouble(),
      evProfileName: json['ev_profile_name'] as String?,
      averageSpeedKph: (json['average_speed_kph'] as num?)?.toDouble() ?? 0,
      peakSpeedKph: (json['peak_speed_kph'] as num?)?.toDouble() ?? 0,
      tripDistanceKm: (json['trip_distance_km'] as num?)?.toDouble() ?? 0,
      smoothDrivingScore:
          (json['smooth_driving_score'] as num?)?.toDouble() ?? 0,
      efficiencyScore: (json['efficiency_score'] as num?)?.toDouble() ?? 0,
      harshEvents: json['harsh_events'] as int? ?? 0,
      elevationM: (json['elevation_m'] as num?)?.toDouble(),
      gradePct: (json['grade_pct'] as num?)?.toDouble(),
      chargeThresholdPct: (json['charge_threshold_pct'] as num?)?.toDouble(),
      predictionRemainingKm:
          (json['prediction_remaining_km'] as num?)?.toDouble(),
      predictionRatePerKm:
          (json['prediction_rate_per_km'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_id': userId,
      'started_at': startedAt.toIso8601String(),
      'session_updated_at': updatedAt.toIso8601String(),
      'device_name': deviceName,
      'device_id': deviceId,
      'battery_percent': batteryPercent,
      'soh_percent': sohPercent,
      'voltage': voltage,
      'battery_power_kw': batteryPowerKw,
      'temperature_c': temperatureC,
      'battery_current_a': batteryCurrentA,
      'cell_delta_mv': cellDeltaMv,
      'ev_profile_name': evProfileName,
      'average_speed_kph': averageSpeedKph,
      'peak_speed_kph': peakSpeedKph,
      'trip_distance_km': tripDistanceKm,
      'smooth_driving_score': smoothDrivingScore,
      'efficiency_score': efficiencyScore,
      'harsh_events': harshEvents,
      'elevation_m': elevationM,
      'grade_pct': gradePct,
      'charge_threshold_pct': chargeThresholdPct,
      'prediction_remaining_km': predictionRemainingKm,
      'prediction_rate_per_km': predictionRatePerKm,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class ObdHistoryAggregate {
  final String label;
  final double totalDistanceKm;
  final double averageEfficiencyScore;
  final double averageSmoothDrivingScore;
  final double averageBatteryPercent;
  final double averageSohPercent;
  final int harshEvents;
  final int sessionCount;

  const ObdHistoryAggregate({
    required this.label,
    required this.totalDistanceKm,
    required this.averageEfficiencyScore,
    required this.averageSmoothDrivingScore,
    required this.averageBatteryPercent,
    required this.averageSohPercent,
    required this.harshEvents,
    required this.sessionCount,
  });
}

class ObdHistoryService {
  static const _keyPrefix = 'obd_history_';
  static const _maxEntriesPerUser = 365;

  ObdHistoryService() : _supabase = Supabase.instance.client;

  final SupabaseClient _supabase;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<List<ObdHistoryEntry>> loadCurrentUserHistory() async {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      return const [];
    }

    final remoteEntries = await _loadRemoteHistoryForUser(userId);
    if (remoteEntries.isNotEmpty) {
      await _cacheHistoryForUser(userId, remoteEntries);
      return remoteEntries;
    }

    final legacyEntries = await _loadLegacyHistoryForUser(userId);
    if (legacyEntries.isNotEmpty) {
      await _saveRemoteHistoryForUser(userId, legacyEntries);
      return legacyEntries;
    }

    return const [];
  }

  Future<void> upsertCurrentUserEntry(ObdHistoryEntry entry) async {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    final existing = await loadCurrentUserHistory();
    final index = existing.indexWhere((item) => item.sessionId == entry.sessionId);

    if (index >= 0) {
      existing[index] = entry;
    } else {
      existing.insert(0, entry);
    }

    existing.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final trimmed = existing.take(_maxEntriesPerUser).toList();
    await _saveRemoteHistoryForUser(userId, trimmed);
  }

  Future<List<ObdHistoryEntry>> _loadRemoteHistoryForUser(String userId) async {
    try {
      final response = await _supabase
          .from('obd_sessions')
          .select(
            'user_id, session_id, started_at, session_updated_at, '
            'device_name, device_id, battery_percent, soh_percent, voltage, '
            'battery_power_kw, temperature_c, battery_current_a, '
            'cell_delta_mv, ev_profile_name, average_speed_kph, '
            'peak_speed_kph, trip_distance_km, smooth_driving_score, '
            'efficiency_score, harsh_events, elevation_m, grade_pct, '
            'charge_threshold_pct, prediction_remaining_km, '
            'prediction_rate_per_km',
          )
          .eq('user_id', userId)
          .order('session_updated_at', ascending: false)
          .limit(_maxEntriesPerUser);

      return response
          .whereType<Map>()
          .map((item) => ObdHistoryEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveRemoteHistoryForUser(
    String userId,
    List<ObdHistoryEntry> entries,
  ) async {
    final payload =
        entries.take(_maxEntriesPerUser).map((item) => item.toJson()).toList();
    if (payload.isEmpty) {
      await _cacheHistoryForUser(userId, const []);
      return;
    }

    try {
      await _supabase.from('obd_sessions').upsert(
        payload,
        onConflict: 'user_id,session_id',
      );
    } catch (_) {
      await _saveLegacyProfileHistoryForUser(userId, entries);
    }

    await _cacheHistoryForUser(userId, entries);
  }

  Future<List<ObdHistoryEntry>> _loadLegacyHistoryForUser(String userId) async {
    final legacyProfileEntries = await _loadLegacyProfileHistoryForUser(userId);
    if (legacyProfileEntries.isNotEmpty) {
      await _cacheHistoryForUser(userId, legacyProfileEntries);
      return legacyProfileEntries;
    }

    return _loadLocalHistoryForUser(userId);
  }

  Future<List<ObdHistoryEntry>> _loadLegacyProfileHistoryForUser(
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('preferences')
          .eq('id', userId)
          .maybeSingle();

      if (response == null) {
        return const [];
      }

      final preferences = response['preferences'];
      if (preferences is! Map) {
        return const [];
      }

      final rawEntries = preferences['obd_history_entries'];
      if (rawEntries is! List) {
        return const [];
      }

      return rawEntries
          .whereType<Map>()
          .map((item) => ObdHistoryEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveLegacyProfileHistoryForUser(
    String userId,
    List<ObdHistoryEntry> entries,
  ) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('preferences')
          .eq('id', userId)
          .maybeSingle();

      final existingPreferences = response == null
          ? <String, dynamic>{}
          : response['preferences'] is Map
          ? Map<String, dynamic>.from(response['preferences'] as Map)
          : <String, dynamic>{};

      final nextPreferences = Map<String, dynamic>.from(existingPreferences)
        ..['obd_history_entries'] = entries.take(_maxEntriesPerUser).map((item) => item.toJson()).toList();

      await _supabase
          .from('profiles')
          .update({'preferences': nextPreferences}).eq('id', userId);
    } catch (_) {
      // Keep local cache as the last fallback when remote persistence is unavailable.
    }
  }

  Future<List<ObdHistoryEntry>> _loadLocalHistoryForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$userId');
    if (raw == null || raw.isEmpty) {
      return <ObdHistoryEntry>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <ObdHistoryEntry>[];
    }

    return decoded
        .whereType<Map>()
        .map((item) => ObdHistoryEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _cacheHistoryForUser(
    String userId,
    List<ObdHistoryEntry> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_keyPrefix$userId',
      jsonEncode(entries.map((item) => item.toJson()).toList()),
    );
  }

  ObdHistoryAggregate aggregateForCurrentMonth(List<ObdHistoryEntry> entries) {
    final now = DateTime.now();
    final monthEntries = entries
        .where(
          (entry) =>
              entry.updatedAt.year == now.year &&
              entry.updatedAt.month == now.month,
        )
        .toList();
    return _aggregate(
      label: DateFormat('MMMM yyyy').format(now),
      entries: monthEntries,
    );
  }

  ObdHistoryAggregate aggregateForCurrentYear(List<ObdHistoryEntry> entries) {
    final now = DateTime.now();
    final yearEntries =
        entries.where((entry) => entry.updatedAt.year == now.year).toList();
    return _aggregate(
      label: now.year.toString(),
      entries: yearEntries,
    );
  }

  List<ObdHistoryAggregate> aggregateByMonth(List<ObdHistoryEntry> entries) {
    final buckets = <String, List<ObdHistoryEntry>>{};

    for (final entry in entries) {
      final key = DateFormat('yyyy-MM').format(entry.updatedAt);
      buckets.putIfAbsent(key, () => <ObdHistoryEntry>[]).add(entry);
    }

    final sortedKeys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedKeys.map((key) {
      final date = DateTime.parse('$key-01');
      return _aggregate(
        label: DateFormat('MMM yyyy').format(date),
        entries: buckets[key]!,
      );
    }).toList();
  }

  ObdHistoryAggregate _aggregate({
    required String label,
    required List<ObdHistoryEntry> entries,
  }) {
    if (entries.isEmpty) {
      return ObdHistoryAggregate(
        label: label,
        totalDistanceKm: 0,
        averageEfficiencyScore: 0,
        averageSmoothDrivingScore: 0,
        averageBatteryPercent: 0,
        averageSohPercent: 0,
        harshEvents: 0,
        sessionCount: 0,
      );
    }

    double averageOf(Iterable<double?> values) {
      final filtered = values.whereType<double>().toList();
      if (filtered.isEmpty) return 0;
      return filtered.reduce((a, b) => a + b) / filtered.length;
    }

    return ObdHistoryAggregate(
      label: label,
      totalDistanceKm: entries.fold<double>(
        0,
        (sum, entry) => sum + entry.tripDistanceKm,
      ),
      averageEfficiencyScore:
          entries.fold<double>(
            0,
            (sum, entry) => sum + entry.efficiencyScore,
          ) /
          entries.length,
      averageSmoothDrivingScore:
          entries.fold<double>(
            0,
            (sum, entry) => sum + entry.smoothDrivingScore,
          ) /
          entries.length,
      averageBatteryPercent:
          averageOf(entries.map((entry) => entry.batteryPercent)),
      averageSohPercent: averageOf(entries.map((entry) => entry.sohPercent)),
      harshEvents: entries.fold<int>(
        0,
        (sum, entry) => sum + entry.harshEvents,
      ),
      sessionCount: entries.length,
    );
  }
}

ObdHistoryEntry buildObdHistoryEntry({
  required String sessionId,
  required DateTime startedAt,
  required ObdTelemetrySnapshot telemetry,
  required DriverAnalytics analytics,
  required ObdScanDevice? device,
  required String userId,
  SocPrediction? prediction,
  double? chargeThresholdPct,
}) {
  return ObdHistoryEntry(
    sessionId: sessionId,
    userId: userId,
    startedAt: startedAt,
    updatedAt: DateTime.now(),
    deviceName: device?.name,
    deviceId: device?.macAddress ?? device?.id,
    batteryPercent: telemetry.batteryPercent,
    sohPercent: telemetry.estimatedSohPercent,
    voltage: telemetry.batteryPackVoltage ?? telemetry.controlModuleVoltage,
    batteryPowerKw: telemetry.batteryPowerKw,
    temperatureC: telemetry.batteryTempC ?? telemetry.coolantTempC,
    batteryCurrentA: telemetry.batteryCurrent,
    cellDeltaMv: telemetry.cellDeltaMv,
    evProfileName: telemetry.evProfileName,
    averageSpeedKph: analytics.averageSpeedKph,
    peakSpeedKph: analytics.peakSpeedKph,
    tripDistanceKm: analytics.tripDistanceKm,
    smoothDrivingScore: analytics.smoothDrivingScore,
    efficiencyScore: analytics.efficiencyScore,
    harshEvents:
        analytics.harshAccelerationEvents + analytics.harshBrakingEvents,
    elevationM: telemetry.elevationM,
    gradePct: telemetry.gradePct,
    chargeThresholdPct: chargeThresholdPct,
    predictionRemainingKm: prediction?.remainingKm,
    predictionRatePerKm: prediction?.depletionRatePerKm,
  );
}
