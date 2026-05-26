import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connectivity_service.dart';

/// A thin amber banner that appears at the top of a screen when the device is
/// offline. Pass [cacheLabel] to show the freshness of whatever cached data
/// is currently being displayed (e.g. "Updated 12 min ago").
///
/// Usage — wrap the Scaffold body or Stack with this:
/// ```dart
/// Column(children: [
///   const OfflineBanner(),
///   Expanded(child: myContent),
/// ])
/// ```
/// Or inside a Stack for overlay mode:
/// ```dart
/// Positioned(
///   top: MediaQuery.of(context).padding.top,
///   left: 0, right: 0,
///   child: OfflineBanner(cacheLabel: entry.freshnessLabel),
/// )
/// ```
class OfflineBanner extends ConsumerWidget {
  /// Optional label appended after the offline message, e.g. "Updated 12 min ago".
  final String? cacheLabel;

  const OfflineBanner({super.key, this.cacheLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    if (isOnline) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final label = cacheLabel != null ? ' · $cacheLabel' : '';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        color: Colors.amber.shade700,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'You\'re offline — showing cached data$label',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
