import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mapping/app_drawer.dart';
import '../../core/ad_banner_widget.dart';
import '../authentication/user_provider.dart';
import '../community/gamification_widgets.dart';
import '../vehicle_profile/vehicle_provider.dart';
import '../../core/app_config.dart';

class MainScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainScreen({super.key, required this.navigationShell});

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final vehicles = ref.watch(vehicleProvider);
    final showVehicleSetupBadge = user != null && vehicles.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EVraahein'),
        centerTitle: false,
        toolbarHeight: 44,
        actions: [
          if (AppConfig.sosEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.icon(
                onPressed: () => context.push('/sos'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.sos, size: 20),
                label: const Text('SOS'),
              ),
            ),
          // Points Badge - shows user's current points
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: PointsBadge(points: user.points, compact: true),
            ),
          // TODO: Enable wallet feature when ready
          // IconButton(
          //   icon: Icon(PhosphorIcons.wallet(PhosphorIconsStyle.duotone)),
          //   onPressed: () {
          //     ScaffoldMessenger.of(context).showSnackBar(
          //       const SnackBar(content: Text('Wallet feature coming soon!')),
          //     );
          //   },
          //   tooltip: 'Wallet',
          // ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(PhosphorIcons.userCircle(PhosphorIconsStyle.duotone)),
                if (showVehicleSetupBadge)
                  Positioned(
                    right: -2,
                    top: -3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC857),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '!',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () => context.push('/profile'),
            tooltip:
                showVehicleSetupBadge
                    ? 'Profile - add your vehicle'
                    : 'Profile',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [Expanded(child: navigationShell), const AdBannerWidget()],
      ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: [
          NavigationDestination(
            icon: Icon(PhosphorIcons.mapTrifold(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(
              PhosphorIcons.mapTrifold(PhosphorIconsStyle.fill),
            ),
            label: 'Find',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIcons.path(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(PhosphorIcons.path(PhosphorIconsStyle.fill)),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIcons.lightning(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(
              PhosphorIcons.lightning(PhosphorIconsStyle.fill),
            ),
            label: 'Charge',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIcons.usersThree(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(
              PhosphorIcons.usersThree(PhosphorIconsStyle.fill),
            ),
            label: 'Community',
          ),
        ],
      ),
    );
  }
}
