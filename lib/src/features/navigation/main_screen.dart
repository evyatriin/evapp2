import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mapping/app_drawer.dart';
import '../../core/ad_banner_widget.dart';

class MainScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainScreen({
    super.key,
    required this.navigationShell,
  });

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EV-Ranger'),
        centerTitle: false,
        actions: [
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
            icon: Icon(PhosphorIcons.userCircle(PhosphorIconsStyle.duotone)),
            onPressed: () => context.push('/profile'),
            tooltip: 'Profile',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Expanded(child: navigationShell),
          const AdBannerWidget(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 60, // Reduced from default 80
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
            label: 'Resources',
          ),
        ],
      ),
    );
  }
}
