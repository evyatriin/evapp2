import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import '../authentication/user_provider.dart';

class ProfileSettingsScreen extends ConsumerWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        centerTitle: true,
      ),
      body: user == null
          ? const Center(child: Text('Please login'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
import '../community/gamification_widgets.dart';
import '../community/gamification_service.dart';

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
                              child: Text(
                                user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                            const Gap(16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.name, style: theme.textTheme.titleLarge),
                                  Text(user.email, style: theme.textTheme.bodyMedium),
                                  const Gap(4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 16,
                                        color: user.isPhoneVerified ? Colors.blue : Colors.grey,
                                      ),
                                      const Gap(4),
                                      Text(
                                        user.isPhoneVerified ? 'Verified' : 'Unverified',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: user.isPhoneVerified ? Colors.blue : Colors.grey,
                                        ),
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
                        const Gap(24),
                        
                        // Stats Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                PointsBadge(points: user.points),
                                const Gap(4),
                                Text('Total Points', style: theme.textTheme.bodySmall),
                              ],
                            ),
                            Column(
                              children: [
                                StreakWidget(streak: user.streak),
                                const Gap(4),
                                Text('Current Streak', style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ],
                        ),
                        
                        const Gap(24),
                        const Divider(),
                        const Gap(16),
                        
                        // Badges Section
                        Text('Badges', style: theme.textTheme.titleMedium),
                        const Gap(16),
                        SizedBox(
                          height: 100,
                          child: FutureBuilder<List<Badge>>(
                            future: GamificationService().getBadges(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              
                              final allBadges = snapshot.data ?? [];
                              final userBadgeIds = user.badges;
                              
                              if (allBadges.isEmpty) {
                                return const Center(child: Text('No badges available'));
                              }

                              return ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: allBadges.length,
                                separatorBuilder: (context, index) => const Gap(16),
                                itemBuilder: (context, index) {
                                  final badge = allBadges[index];
                                  final isUnlocked = userBadgeIds.contains(badge.id);
                                  return BadgeWidget(
                                    badge: badge,
                                    isLocked: !isUnlocked,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Gap(16),
                // Security Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Security', style: theme.textTheme.titleLarge),
                        const Gap(8),
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Change Password'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/profile/change-password'),
                        ),
                      ],
                    ),
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
                        Text('Account Settings', style: theme.textTheme.titleLarge),
                        const Gap(16),
                        ListTile(
                          leading: const Icon(Icons.map),
                          title: const Text('Saved Routes'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/saved-routes'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Logout'),
                          onTap: () => _showLogoutDialog(context, ref),
                        ),
                        ListTile(
                          leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          title: Text('Delete Account', style: TextStyle(color: theme.colorScheme.error)),
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

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to delete your account? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              // TODO: Implement actual account deletion via backend
              await ref.read(userProvider.notifier).signOut();
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
