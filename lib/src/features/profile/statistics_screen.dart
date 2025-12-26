import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) => RefreshIndicator(
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
                          color: Colors.green,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${stats.co2SavedKg.toStringAsFixed(1)} kg',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
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
                      color: Colors.blue,
                    ),
                    _StatCard(
                      icon: PhosphorIcons.lightning(PhosphorIconsStyle.duotone),
                      label: 'Energy Charged',
                      value: '${stats.totalKwhCharged.toStringAsFixed(1)} kWh',
                      color: Colors.orange,
                    ),
                    _StatCard(
                      icon: PhosphorIcons.currencyInr(PhosphorIconsStyle.duotone),
                      label: 'Money Saved',
                      value: '₹${stats.moneySaved.toStringAsFixed(0)}',
                      color: Colors.green,
                    ),
                    _StatCard(
                      icon: PhosphorIcons.mapPin(PhosphorIconsStyle.duotone),
                      label: 'Check-ins',
                      value: '${stats.totalCheckIns}',
                      color: Colors.purple,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Trips Section
                Text(
                  'Recent Activity',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                if (stats.totalTrips == 0)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            PhosphorIcons.car(PhosphorIconsStyle.duotone),
                            size: 48,
                            color: theme.colorScheme.secondary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No trips logged yet',
                            style: theme.textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Start driving and check-in at stations!',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: Icon(PhosphorIcons.path(PhosphorIconsStyle.duotone)),
                      title: Text('${stats.totalTrips} trips logged'),
                      subtitle: Text('Average ${stats.totalTrips > 0 ? (stats.totalKm / stats.totalTrips).toStringAsFixed(0) : 0} km per trip'),
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
                      Icon(PhosphorIcons.info(PhosphorIconsStyle.duotone), 
                           size: 20, color: theme.colorScheme.secondary),
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
