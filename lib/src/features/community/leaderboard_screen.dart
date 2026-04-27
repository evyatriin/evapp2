import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:gap/gap.dart';
import 'gamification_service.dart';
import 'gamification_widgets.dart';
import '../authentication/user_provider.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  final _gamificationService = GamificationService();
  List<LeaderboardEntry> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);
    final entries = await _gamificationService.getLeaderboard();
    if (mounted) {
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLeaderboard,
          ),
        ],
      ),
      body: _isLoading
          ? _LeaderboardState(
              icon: PhosphorIcons.trophy(PhosphorIconsStyle.duotone),
              title: 'Loading community leaderboard',
              subtitle: 'Refreshing streaks and points from the latest activity.',
              child: const CircularProgressIndicator(),
            )
          : _entries.isEmpty
              ? _LeaderboardState(
                  icon: PhosphorIcons.usersThree(PhosphorIconsStyle.duotone),
                  title: 'No leaderboard movement yet',
                  subtitle: 'As members check in, save routes, and build streaks, rankings will appear here.',
                  child: FilledButton.icon(
                    onPressed: _loadLeaderboard,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (context, index) => const Gap(12),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    final isMe = entry.userId == currentUser?.id;
                    
                    return _buildLeaderboardItem(context, entry, isMe);
                  },
                ),
    );
  }

  Widget _buildLeaderboardItem(BuildContext context, LeaderboardEntry entry, bool isMe) {
    final theme = Theme.of(context);
    
    Color? rankColor;
    IconData? rankIcon;
    
    if (entry.rank == 1) {
      rankColor = theme.colorScheme.tertiary;
      rankIcon = PhosphorIcons.crown(PhosphorIconsStyle.fill);
    } else if (entry.rank == 2) {
      rankColor = theme.colorScheme.secondary;
    } else if (entry.rank == 3) {
      rankColor = theme.colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isMe ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 40,
            child: rankIcon != null
                ? Icon(rankIcon, color: rankColor, size: 24)
                : Text(
                    '#${entry.rank}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
          ),
          const Gap(12),
          
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundImage: entry.profileImageUrl != null
                ? ResizeImage(
                    NetworkImage(entry.profileImageUrl!),
                    width: 40, // 20 * 2
                    height: 40,
                  )
                : null,
            child: entry.profileImageUrl == null
                ? Text(entry.name.isNotEmpty ? entry.name[0].toUpperCase() : '?')
                : null,
          ),
          const Gap(12),
          
          // Name & Streak
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name.isNotEmpty ? entry.name : 'Anonymous',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.currentStreak > 0)
                  Row(
                    children: [
                      Icon(PhosphorIcons.fire(PhosphorIconsStyle.fill), size: 12, color: Colors.orange),
                      const Gap(4),
                      Text(
                        '${entry.currentStreak} day streak',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          
          // Points
          PointsBadge(points: entry.totalPoints, compact: true),
        ],
      ),
    );
  }
}

class _LeaderboardState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _LeaderboardState({
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
              child: Icon(icon, size: 36, color: theme.colorScheme.primary),
            ),
            const Gap(18),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const Gap(18),
            child,
          ],
        ),
      ),
    );
  }
}
