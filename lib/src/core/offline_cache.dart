import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple JSON cache backed by SharedPreferences.
///
/// Every entry is stored as `{data, fetchedAt}` so the UI can always show
/// how fresh the cached data is. Keys are prefixed to avoid collisions.
///
/// Usage:
/// ```dart
/// // Write
/// await OfflineCache.set(OfflineCache.vehiclesKey, vehicleListJson);
///
/// // Read
/// final entry = await OfflineCache.get(OfflineCache.vehiclesKey);
/// if (entry != null) {
///   print('${entry.freshnessLabel}');   // e.g. "Updated 12 min ago"
///   final data = entry.data;
/// }
/// ```
class OfflineCache {
  static const _prefix = 'offline_cache_v1_';

  // ── Well-known cache keys ─────────────────────────────────────────────────
  static const String savedRoutesKey = 'saved_routes';
  static const String userProfileKey = 'user_profile';
  static const String vehiclesKey = 'vehicles';
  static const String savedChargersKey = 'saved_chargers';

  /// Build a per-route charger cache key. Coordinates are rounded to 2 d.p.
  /// so nearby trips reuse the same cache entry.
  static String chargersRouteKey(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) {
    return 'chargers'
        '_${originLat.toStringAsFixed(2)}'
        '_${originLng.toStringAsFixed(2)}'
        '_${destLat.toStringAsFixed(2)}'
        '_${destLng.toStringAsFixed(2)}';
  }

  // ── Read / Write / Delete ─────────────────────────────────────────────────

  /// Store [data] under [key]. [data] must be JSON-serialisable.
  static Future<void> set(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'data': data,
        'fetchedAt': DateTime.now().toIso8601String(),
      });
      await prefs.setString('$_prefix$key', encoded);
    } catch (e) {
      debugPrint('[OfflineCache] write failed for "$key": $e');
    }
  }

  /// Retrieve the cached [CacheEntry] for [key], or `null` if nothing stored.
  static Future<CacheEntry?> get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CacheEntry(
        data: map['data'],
        fetchedAt: DateTime.parse(map['fetchedAt'] as String),
      );
    } catch (e) {
      debugPrint('[OfflineCache] read failed for "$key": $e');
      return null;
    }
  }

  /// Delete a cache entry (e.g. after logout or explicit refresh).
  static Future<void> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
    } catch (e) {
      debugPrint('[OfflineCache] remove failed for "$key": $e');
    }
  }

  /// Delete ALL cache entries (nuclear option — use on logout).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (e) {
      debugPrint('[OfflineCache] clear failed: $e');
    }
  }
}

// ─── Cache entry ─────────────────────────────────────────────────────────────

class CacheEntry {
  final dynamic data;
  final DateTime fetchedAt;

  const CacheEntry({required this.data, required this.fetchedAt});

  Duration get age => DateTime.now().difference(fetchedAt);

  /// Human-readable freshness label for display in the UI.
  String get freshnessLabel {
    final mins = age.inMinutes;
    if (mins < 1) return 'Just now';
    if (mins < 60) return 'Updated ${mins}m ago';
    final hours = age.inHours;
    if (hours < 24) return 'Updated ${hours}h ago';
    return 'Updated ${age.inDays}d ago';
  }

  /// Source label shown alongside charger/route data.
  String get sourceBadge => isStale ? 'Cached (stale)' : 'Cached';

  /// Stale = older than 24 hours; derank stale entries in UX.
  bool get isStale => age.inHours >= 24;
}
