import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/navigation_helpers.dart';
import 'statistics_service.dart';
import '../authentication/user_provider.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(userProvider);
    final statsAsync = ref.watch(userStatisticsProvider(user?.id ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Statistics'),
        actions: [
          IconButton(
            onPressed: () => openObdAnalytics(context),
            icon: const Icon(Icons.battery_charging_full),
            tooltip: 'OBD Analytics',
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => _StateScaffold(
          icon: PhosphorIcons.chartBar(PhosphorIconsStyle.duotone),
          title: 'Loading your driving story',
          subtitle: 'Summarizing distance, charging, and impact from your recent trips.',
          child: const CircularProgressIndicator(),
        ),
        error: (e, _) => _StateScaffold(
          icon: PhosphorIcons.warningCircle(PhosphorIconsStyle.duotone),
          title: 'Statistics are unavailable right now',
          subtitle: 'We could not load your trip insights. Pull to retry in a moment.',
          child: const SizedBox.shrink(),
        ),
        data:
            (stats) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(userStatisticsProvider(user?.id ?? ''));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero Stats Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Icon(
                              PhosphorIcons.leaf(PhosphorIconsStyle.duotone),
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${stats.co2SavedKg.toStringAsFixed(1)} kg',
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              'CO₂ Saved',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Equivalent to ${(stats.co2SavedKg / 21).toStringAsFixed(0)} trees planted 🌳',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Stats Grid
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.4,
                      children: [
                        _StatCard(
                          icon: PhosphorIcons.path(PhosphorIconsStyle.duotone),
                          label: 'Total Distance',
                          value: '${stats.totalKm.toStringAsFixed(0)} km',
                          color: theme.colorScheme.secondary,
                        ),
                        _StatCard(
                          icon: PhosphorIcons.lightning(
                            PhosphorIconsStyle.duotone,
                          ),
                          label: 'Energy Charged',
                          value:
                              '${stats.totalKwhCharged.toStringAsFixed(1)} kWh',
                          color: theme.colorScheme.tertiary,
                        ),
                        _StatCard(
                          icon: PhosphorIcons.currencyInr(
                            PhosphorIconsStyle.duotone,
                          ),
                          label: 'Money Saved',
                          value: '₹${stats.moneySaved.toStringAsFixed(0)}',
                          color: theme.colorScheme.primary,
                        ),
                        _StatCard(
                          icon: PhosphorIcons.mapPin(
                            PhosphorIconsStyle.duotone,
                          ),
                          label: 'Check-ins',
                          value: '${stats.totalCheckIns}',
                          color: theme.colorScheme.error,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Trips Section
                    Text(
                      'Recent Activity',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (stats.totalTrips == 0)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  PhosphorIcons.car(PhosphorIconsStyle.duotone),
                                  size: 28,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your statistics will build up as you drive',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Plan a route, log a charge session, or check in at a station to start tracking your EV impact.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        child: ListTile(
                          leading: Icon(
                            PhosphorIcons.path(PhosphorIconsStyle.duotone),
                          ),
                          title: Text('${stats.totalTrips} trips logged'),
                          subtitle: Text(
                            'Average ${stats.totalTrips > 0 ? (stats.totalKm / stats.totalTrips).toStringAsFixed(0) : 0} km per trip',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIcons.info(PhosphorIconsStyle.duotone),
                            size: 20,
                            color: theme.colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'CO₂ savings calculated vs. average petrol car (120g/km)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StateScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _StateScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}
