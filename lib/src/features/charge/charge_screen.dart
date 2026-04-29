import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import 'charging_service.dart';
import '../community/check_in_sheet.dart';
import '../community/moderation_service.dart';
import '../authentication/user_provider.dart';
import '../authentication/auth_service.dart';

class ChargeScreen extends ConsumerStatefulWidget {
  const ChargeScreen({super.key});

  @override
  ConsumerState<ChargeScreen> createState() => _ChargeScreenState();
}

class _ChargeScreenState extends ConsumerState<ChargeScreen>
    with SingleTickerProviderStateMixin {
  final _chargingService = ChargingService();
  List<dynamic> _checkIns = [];
  List<dynamic> _publicCheckIns = [];
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadHistory();
    _loadPublicCheckIns();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final user = ref.read(userProvider);
      if (user == null) {
        setState(() {
          _isLoading = false;
          _error = "User not logged in";
        });
        return;
      }

      final checkIns = await _chargingService.getCheckIns(user.id);
      if (mounted) {
        setState(() {
          _checkIns = checkIns;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPublicCheckIns() async {
    final checkIns = await _chargingService.getPublicCheckIns(limit: 50);
    if (mounted) {
      setState(() {
        _publicCheckIns = checkIns;
      });
    }
  }

  Future<void> _vote(String checkinId, String voteType) async {
    final user = ref.read(userProvider);
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in to vote')));
      return;
    }

    final result = await _chargingService.voteCheckIn(
      userId: user.id,
      checkinId: checkinId,
      voteType: voteType,
    );

    if (result != null) {
      // Update local state
      setState(() {
        final index = _publicCheckIns.indexWhere((c) => c['id'] == checkinId);
        if (index != -1) {
          _publicCheckIns[index]['upvotes'] = result['upvotes'];
          _publicCheckIns[index]['downvotes'] = result['downvotes'];
        }
      });
    }
  }

  Future<void> _showModerationMenu({
    String? reportedUserId,
    required String reportedUserName,
  }) async {
    if (reportedUserId == null) return;
    final me = ref.read(userProvider);
    if (me == null) return;
    if (me.id == reportedUserId) return; // can't report yourself
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text('Report $reportedUserName'),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.red),
              title: Text('Block $reportedUserName'),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final token = AuthService().getAuthToken();
    if (token == null) return;
    final svc = ModerationService();

    try {
      if (action == 'report') {
        final reason = await _promptReportReason();
        if (reason == null || reason.isEmpty) return;
        await svc.reportUser(
          reporterId: me.id,
          reportedUserId: reportedUserId,
          reason: reason,
          authToken: token,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Our team will review it.')),
        );
      } else {
        await svc.blockUser(
          blockerId: me.id,
          blockedId: reportedUserId,
          authToken: token,
        );
        if (!mounted) return;
        setState(() {
          _publicCheckIns.removeWhere((c) => c['user_id'] == reportedUserId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$reportedUserName blocked.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  Future<String?> _promptReportReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Why are you reporting this?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Spam, abusive content, fake review, etc.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final workingCheckIns =
        _checkIns.where((c) => c['status'] == 'Working').toList();
    final issueCheckIns =
        _checkIns.where((c) => c['status'] != 'Working').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Charging Hub'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: const [
              Tab(text: 'My Charges', height: 36),
              Tab(text: 'Community Reviews', height: 36),
              Tab(text: 'Issues', height: 36),
            ],
          ),
        ),
      ),
      body:
          _isLoading
              ? const _ChargeStateView(
                icon: Icons.bolt,
                title: 'Loading charging activity',
                subtitle: 'Fetching your history and live community check-ins.',
                loading: true,
              )
              : _error != null
              ? _ChargeStateView(
                icon: Icons.error_outline,
                title: 'Couldn\'t load charging data',
                subtitle: _error!,
              )
              : TabBarView(
                controller: _tabController,
                children: [
                  RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: _buildList(workingCheckIns, theme, true),
                  ),
                  RefreshIndicator(
                    onRefresh: _loadPublicCheckIns,
                    child: _buildPublicReviewsList(theme),
                  ),
                  RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: _buildList(issueCheckIns, theme, false),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (context) => const CheckInSheet(),
          ).then((_) {
            _loadHistory();
            _loadPublicCheckIns();
          });
        },
        icon: Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.duotone)),
        label: const Text('Check-In'),
      ),
    );
  }

  Widget _buildPublicReviewsList(ThemeData theme) {
    if (_publicCheckIns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.usersThree(PhosphorIconsStyle.duotone),
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No community reviews yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Be the first to check-in!', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _publicCheckIns.length,
      itemBuilder: (context, index) {
        final item = _publicCheckIns[index];
        final createdAt = DateTime.parse(item['created_at']);
        final status = item['status'] ?? 'Unknown';
        final rating = item['rating'];
        final comment = item['comment'];
        final userName = item['user_name'] ?? 'A***r';
        final upvotes = item['upvotes'] ?? 0;
        final downvotes = item['downvotes'] ?? 0;
        final checkinId = item['id'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onLongPress: () => _showModerationMenu(
              reportedUserId: item['user_id']?.toString(),
              reportedUserName: userName.toString(),
            ),
            child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: User + Time
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            DateFormat.yMMMd().add_jm().format(createdAt),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            status == 'Working'
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color:
                              status == 'Working'
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                // Comment
                if (comment != null && comment.toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '"$comment"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Rating + Votes
                Row(
                  children: [
                    if (rating != null) ...[
                      Row(
                        children: [
                          Text(
                            rating.toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                    ],
                    const Spacer(),
                    // Upvote button
                    InkWell(
                      onTap: () => _vote(checkinId, 'upvote'),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIcons.thumbsUp(PhosphorIconsStyle.duotone),
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$upvotes',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Downvote button
                    InkWell(
                      onTap: () => _vote(checkinId, 'downvote'),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIcons.thumbsDown(
                              PhosphorIconsStyle.duotone,
                            ),
                            size: 20,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$downvotes',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildList(List<dynamic> items, ThemeData theme, bool isSuccess) {
    if (items.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChargeSummaryCard(
                label:
                    isSuccess
                        ? 'Successful sessions'
                        : 'Reported issues',
                count: items.length,
                accent:
                    isSuccess
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
              ),
            );
          }
          final item = items[index - 1];
          final createdAt = DateTime.parse(item['created_at']);
          final status = item['status'];
          final rating = item['rating'];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    isSuccess
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.errorContainer,
                child: Icon(
                  isSuccess
                      ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                      : PhosphorIcons.warning(PhosphorIconsStyle.bold),
                  color:
                      isSuccess
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                ),
              ),
              title: Text(DateFormat.yMMMd().add_jm().format(createdAt)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: $status'),
                  if (item['comment'] != null &&
                      item['comment'].toString().isNotEmpty)
                    Text(
                      '"${item['comment']}"',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
              trailing:
                  rating != null
                      ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            rating.toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Icon(
                            Icons.star,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                        ],
                      )
                      : null,
            ),
          );
        },
      );
    }

    if (items.isEmpty) {
      return _ChargeStateView(
        icon:
            isSuccess
                ? PhosphorIcons.lightning(PhosphorIconsStyle.duotone)
                : PhosphorIcons.warning(PhosphorIconsStyle.duotone),
        title:
            isSuccess ? 'No charging sessions yet' : 'No issues reported',
        subtitle:
            isSuccess
                ? 'Your successful sessions will appear here after your first check-in.'
                : 'You\'re all clear for now. Report problems if a charger misbehaves.',
      );
    }
    return const SizedBox.shrink();
  }
}

class _ChargeSummaryCard extends StatelessWidget {
  final String label;
  final int count;
  final Color accent;

  const _ChargeSummaryCard({
    required this.label,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            theme.colorScheme.surfaceContainerLowest,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Icon(Icons.bolt, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                Text(
                  '$count entries',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChargeStateView extends StatelessWidget {
  final Object icon;
  final String title;
  final String subtitle;
  final bool loading;

  const _ChargeStateView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const CircularProgressIndicator()
              else if (icon is IconData)
                Icon(icon as IconData, size: 42, color: theme.colorScheme.primary)
              else
                Icon(
                  icon as PhosphorIconData,
                  size: 42,
                  color: theme.colorScheme.primary,
                ),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
