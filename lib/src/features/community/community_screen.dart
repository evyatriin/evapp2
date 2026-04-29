import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'trending_tab.dart';
import 'resources_tab.dart';
import 'leaderboard_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community'),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => context.push('/sos'),
                icon: const Icon(Icons.sos, size: 16),
                label: const Text('SOS'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
              ),
            ),
          ],
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(36),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                Tab(text: 'Trending', height: 36),
                Tab(text: 'Guides', height: 36),
                Tab(text: 'Leaderboard', height: 36),
              ],
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            TrendingTab(),
            ResourcesTab(),
            LeaderboardScreen(),
          ],
        ),
      ),
    );
  }
}
