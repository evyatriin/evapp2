import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../authentication/user_model.dart';
import '../authentication/user_provider.dart';
import '../authentication/verification_gate.dart';
import '../community/gamification_widgets.dart';
import '../community/gamification_service.dart';
import '../vehicle_profile/vehicle_provider.dart';
import '../vehicle_profile/vehicle_model.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:io';

class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(userProvider);
    final vehicles = ref.watch(vehicleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
      ),
      body:
          user == null
              ? const Center(child: Text('Please login'))
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Profile Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: theme.colorScheme.primaryContainer,
                                child: Text(
                                  user.name.isNotEmpty
                                      ? user.name[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.name,
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    Text(
                                      user.email,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const Gap(10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _verifyChip(context, ref, theme, user),
                                        PointsBadge(
                                          points: user.points,
                                          compact: true,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => context.push('/profile/edit'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(16),

                  // Badges — only shown when the user actually has badges.
                  _badgesCard(context, theme, user),

                  // My Vehicles Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'My Vehicles',
                                style: theme.textTheme.titleLarge,
                              ),
                              IconButton(
                                icon: Icon(
                                  PhosphorIcons.plusCircle(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  color: theme.colorScheme.primary,
                                ),
                                tooltip: 'Add Vehicle',
                                onPressed:
                                    () => context.push('/setup/vehicle/add'),
                              ),
                            ],
                          ),
                          const Gap(12),
                          if (vehicles.isEmpty)
                            _buildEmptyVehicleState(context, theme)
                          else
                            SizedBox(
                              height: 160,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: vehicles.length,
                                separatorBuilder:
                                    (context, index) => const Gap(12),
                                itemBuilder: (context, index) {
                                  final vehicle = vehicles[index];
                                  return _VehicleCard(
                                    vehicle: vehicle,
                                    onTap:
                                        () => context.push(
                                          '/setup/vehicle/edit',
                                          extra: vehicle,
                                        ),
                                    onSetPrimary:
                                        () => ref
                                            .read(vehicleProvider.notifier)
                                            .setPrimaryVehicle(vehicle.id),
                                    onDelete:
                                        () => _showDeleteVehicleDialog(
                                          context,
                                          ref,
                                          vehicle,
                                        ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(16),

                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.add_home_work_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: const Text('Community Charging'),
                      subtitle: const Text('Share your charger or request one'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/community-charging'),
                    ),
                  ),
                  const Gap(16),

                  // Account Settings
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account Settings',
                            style: theme.textTheme.titleLarge,
                          ),
                          const Gap(16),
                          ListTile(
                            leading: const Icon(Icons.lock_outline),
                            title: const Text('Change Password'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap:
                                () => context.push('/profile/change-password'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.logout),
                            title: const Text('Logout'),
                            onTap: () => _showLogoutDialog(context, ref),
                          ),
                          ListTile(
                            leading: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error,
                            ),
                            title: Text(
                              'Delete Account',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                            onTap: () => _showDeleteAccountDialog(context, ref),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const Gap(5),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _verifyChip(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    UserProfile user,
  ) {
    if (user.isDoubleVerified) {
      return _chip(
        icon: Icons.verified,
        label: 'Verified',
        bg: AppTheme.electricLime,
        fg: const Color(0xFF0A2E14),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () async {
        final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => const PhoneVerificationSheet(),
        );
        if (ok == true) ref.read(userProvider.notifier).refresh();
      },
      child: _chip(
        icon: Icons.gpp_maybe_outlined,
        label: 'Verify phone',
        bg: theme.colorScheme.primaryContainer,
        fg: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }

  Widget _badgesCard(BuildContext context, ThemeData theme, UserProfile user) {
    return FutureBuilder<List<Badge>>(
      future: GamificationService().getBadges(),
      builder: (context, snapshot) {
        final allBadges = snapshot.data ?? const <Badge>[];
        if (allBadges.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Badges', style: theme.textTheme.titleMedium),
                  const Gap(16),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: allBadges.length,
                      separatorBuilder: (context, index) => const Gap(16),
                      itemBuilder: (context, index) {
                        final badge = allBadges[index];
                        final isUnlocked = user.badges.contains(badge.id);
                        return BadgeWidget(badge: badge, isLocked: !isUnlocked);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyVehicleState(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            PhosphorIcons.car(PhosphorIconsStyle.duotone),
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const Gap(12),
          Text('No vehicles added yet', style: theme.textTheme.bodyMedium),
          const Gap(12),
          FilledButton.icon(
            onPressed: () => context.push('/setup/vehicle/add'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Vehicle'),
          ),
        ],
      ),
    );
  }

  void _showDeleteVehicleDialog(
    BuildContext context,
    WidgetRef ref,
    VehicleProfile vehicle,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Vehicle'),
            content: Text(
              'Are you sure you want to delete ${vehicle.brand} ${vehicle.model}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () {
                  ref.read(vehicleProvider.notifier).removeVehicle(vehicle.id);
                  Navigator.pop(context);
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  await ref.read(userProvider.notifier).signOut();
                  if (context.mounted) {
                    Navigator.pop(context);
                    context.go('/login');
                  }
                },
                child: const Text('Logout'),
              ),
            ],
          ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Account'),
            content: const Text(
              'Are you sure you want to delete your account? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  await ref.read(userProvider.notifier).deleteAccount();
                  if (context.mounted) {
                    Navigator.pop(context);
                    context.go('/login');
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleProfile vehicle;
  final VoidCallback onTap;
  final VoidCallback onSetPrimary;
  final VoidCallback onDelete;

  const _VehicleCard({
    required this.vehicle,
    required this.onTap,
    required this.onSetPrimary,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                vehicle.isPrimary
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
            width: vehicle.isPrimary ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background: only a real user-uploaded photo becomes a full-bleed
            // image. Template placeholder art stays a clean gradient instead.
            if (vehicle.photoUrl != null)
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.3),
                    BlendMode.darken,
                  ),
                  child: Image(
                    image: _getImageProvider(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      );
                    },
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.surface,
                      ],
                    ),
                  ),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          vehicle.brand,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color:
                              _hasImage()
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              onTap();
                              break;
                            case 'primary':
                              onSetPrimary();
                              break;
                            case 'delete':
                              onDelete();
                              break;
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    Gap(8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              if (!vehicle.isPrimary)
                                const PopupMenuItem(
                                  value: 'primary',
                                  child: Row(
                                    children: [
                                      Icon(Icons.star, size: 18),
                                      Gap(8),
                                      Text('Set as Primary'),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    const Gap(8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (vehicle.isPrimary)
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 12,
                                color: theme.colorScheme.onPrimary,
                              ),
                              const Gap(4),
                              Text(
                                'Primary',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        vehicle.model,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _hasImage() ? Colors.white : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        vehicle.variant,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              _hasImage()
                                  ? Colors.white70
                                  : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Gap(4),
                      Row(
                        children: [
                          Icon(
                            Icons.battery_charging_full,
                            size: 14,
                            color:
                                _hasImage()
                                    ? Colors.white70
                                    : theme.colorScheme.tertiary,
                          ),
                          const Gap(4),
                          Text(
                            '${vehicle.estimatedRange.toInt()} km',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  _hasImage()
                                      ? Colors.white
                                      : theme.colorScheme.tertiary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
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

  bool _hasImage() => vehicle.photoUrl != null;

  ImageProvider _getImageProvider() {
    final url = vehicle.photoUrl;
    if (url != null && url.startsWith('http')) {
      return NetworkImage(url);
    } else if (url != null) {
      return FileImage(File(url));
    }
    return const AssetImage('assets/placeholder.png');
  }
}
