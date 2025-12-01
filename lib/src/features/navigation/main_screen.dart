import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../community/check_in_sheet.dart';

class MainScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScreen({
    super.key,
    required this.navigationShell,
  });

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // A common pattern when using bottom navigation bars is to support
      // navigating to the initial location when tapping the item that is
      // already active. This example demonstrates how to support this behavior,
      // using the initialLocation parameter of goBranch.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('EV-Ranger'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.wallet(PhosphorIconsStyle.duotone)),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Wallet feature coming soon!')),
              );
            },
            tooltip: 'Wallet',
          ),
          IconButton(
            icon: Icon(PhosphorIcons.userCircle(PhosphorIconsStyle.duotone)),
            onPressed: () => context.push('/setup'),
            tooltip: 'Profile',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: const Text('Ranger User'), // Placeholder
              accountEmail: const Text('ranger@ev-ranger.com'), // Placeholder
              currentAccountPicture: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  'R',
                  style: TextStyle(fontSize: 24, color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
              ),
              onDetailsPressed: () {
                context.pop(); // Close drawer
                context.push('/setup');
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.userCircle(PhosphorIconsStyle.duotone)),
              title: const Text('Profile'),
              onTap: () {
                context.pop(); // Close drawer
                context.push('/setup');
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(PhosphorIcons.camera(PhosphorIconsStyle.duotone)),
              title: const Text('Check-In'),
              onTap: () {
                context.pop(); // Close drawer
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => const CheckInSheet(),
                );
              },
            ),
            ListTile(
              leading: Icon(PhosphorIcons.warning(PhosphorIconsStyle.duotone), color: theme.colorScheme.error),
              title: Text('SOS', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                context.pop(); // Close drawer
                context.push('/sos');
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(PhosphorIcons.gear(PhosphorIconsStyle.duotone)),
              title: const Text('Settings'),
              onTap: () {
                context.pop(); // Close drawer
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings coming soon!')),
                );
              },
            ),
          ],
        ),
      ),
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _goBranch,
        destinations: [
          NavigationDestination(
            icon: Icon(PhosphorIcons.mapTrifold(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(PhosphorIcons.mapTrifold(PhosphorIconsStyle.fill)),
            label: 'Find',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIcons.path(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(PhosphorIcons.path(PhosphorIconsStyle.fill)),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIcons.lightning(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(PhosphorIcons.lightning(PhosphorIconsStyle.fill)),
            label: 'Charge',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIcons.usersThree(PhosphorIconsStyle.duotone)),
            selectedIcon: Icon(PhosphorIcons.usersThree(PhosphorIconsStyle.fill)),
            label: 'Community',
          ),
        ],
      ),
    );
  }
}
