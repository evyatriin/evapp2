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
    final theme = Theme.of(context);
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
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIcons.trophy(PhosphorIconsStyle.duotone), size: 64, color: Colors.grey),
                      const Gap(16),
                      Text(
                        'No leaderboard data yet',
                        style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
                      ),
                    ],
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
      rankColor = const Color(0xFFFFD700); // Gold
      rankIcon = PhosphorIcons.crown(PhosphorIconsStyle.fill);
    } else if (entry.rank == 2) {
      rankColor = const Color(0xFFC0C0C0); // Silver
    } else if (entry.rank == 3) {
      rankColor = const Color(0xFFCD7F32); // Bronze
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
                          color: Colors.orange,
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
