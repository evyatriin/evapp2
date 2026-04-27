import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import '../authentication/user_provider.dart';
import 'vehicle_provider.dart';
import 'vehicle_model.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final vehicles = ref.watch(vehicleProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Gap(32),
            // User Profile Section
            CircleAvatar(
              radius: 50,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                (user?.name.isNotEmpty ?? false)
                    ? user!.name[0].toUpperCase()
                    : 'U',
                style: theme.textTheme.displayMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const Gap(16),
            Text(
              user?.name ?? 'Guest',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              user?.email ?? '',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Gap(40),

            // Vehicles Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Vehicles',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/setup/vehicle/add'),
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add Vehicle',
                  ),
                ],
              ),
            ),
            const Gap(16),

            if (vehicles.isEmpty)
              _buildEmptyState(context)
            else
              SizedBox(
                height: 220,
                child: PageView.builder(
                  controller: PageController(viewportFraction: 0.85),
                  itemCount: vehicles.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _VehicleCard(vehicle: vehicles[index]),
                    );
                  },
                ),
              ),

            const Gap(40),
            // Other Profile Options (Placeholder)
            ListTile(
              leading: Icon(PhosphorIcons.gear(PhosphorIconsStyle.duotone)),
              title: const Text('Settings'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
            ListTile(
              leading: Icon(PhosphorIcons.signOut(PhosphorIconsStyle.duotone)),
              title: const Text('Sign Out'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            PhosphorIcons.car(PhosphorIconsStyle.duotone),
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const Gap(16),
          const Text('No vehicles added yet'),
          const Gap(16),
          FilledButton(
            onPressed: () => context.push('/setup/vehicle/add'),
            child: const Text('Add Vehicle'),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends ConsumerWidget {
  final VehicleProfile vehicle;

  const _VehicleCard({required this.vehicle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/setup/vehicle/edit', extra: vehicle),
        child: Stack(
          children: [
            // Background Image
            if (vehicle.imageUrl != null && vehicle.imageUrl!.isNotEmpty)
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.4),
                    BlendMode.darken,
                  ),
                  child: Image(
                    image:
                        vehicle.imageUrl!.startsWith('http')
                            ? NetworkImage(vehicle.imageUrl!)
                            : FileImage(File(vehicle.imageUrl!))
                                as ImageProvider,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      );
                    },
                  ),
                ),
              ),

            // Content
            Container(
              decoration: BoxDecoration(
                gradient:
                    vehicle.imageUrl == null
                        ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.colorScheme.primaryContainer,
                            theme.colorScheme.surface,
                          ],
                        )
                        : null,
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        PhosphorIcons.carProfile(PhosphorIconsStyle.fill),
                        size: 32,
                        color:
                            vehicle.imageUrl != null
                                ? Colors.white
                                : theme.colorScheme.primary,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (vehicle.imageUrl != null
                                  ? Colors.white
                                  : theme.colorScheme.primary)
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          vehicle.brand,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color:
                                vehicle.imageUrl != null
                                    ? Colors.white
                                    : theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    vehicle.model,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: vehicle.imageUrl != null ? Colors.white : null,
                    ),
                  ),
                  Text(
                    vehicle.variant,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          vehicle.imageUrl != null
                              ? Colors.white70
                              : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.batteryCharging(
                          PhosphorIconsStyle.duotone,
                        ),
                        size: 16,
                        color:
                            vehicle.imageUrl != null
                                ? Colors.white70
                                : theme.colorScheme.tertiary,
                      ),
                      const Gap(4),
                      Text(
                        '${vehicle.estimatedRange.toInt()} km range',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color:
                              vehicle.imageUrl != null
                                  ? Colors.white
                                  : theme.colorScheme.tertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
