import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` when the device has any network connection, `false` when fully offline.
final connectivityStreamProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );
});

/// Synchronous online flag. Defaults to `true` until the first event arrives
/// (safe assumption — shows cached data rather than premature offline banner).
final isOnlineProvider = Provider<bool>((ref) {
  final async = ref.watch(connectivityStreamProvider);
  // In Riverpod 3.x AsyncValue exposes `.value` (nullable) directly
  return async.when(
    data: (online) => online,
    loading: () => true,  // assume online while determining state
    error: (_, __) => true,
  );
});

/// One-shot check: is the device online right now?
/// Use inside async handlers where you can't watch a Riverpod provider.
Future<bool> checkConnectivityNow() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}
