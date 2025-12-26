import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'trending_tab.dart';
import 'resources_tab.dart';
import 'leaderboard_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'community_providers.dart';

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community Hub'),
          centerTitle: false,
          toolbarHeight: 48,
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: const [
                Tab(text: 'For You', height: 36),
                Tab(text: 'My Communities', height: 36),
                Tab(text: 'Trending', height: 36),
                Tab(text: 'Resources', height: 36),
                Tab(text: 'Leaderboard', height: 36),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            const _ForYouTab(),
            _buildPlaceholderTab(context, 'My Communities'),
            const TrendingTab(),
            const ResourcesTab(),
            const LeaderboardScreen(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab(BuildContext context, String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIcons.wrench(PhosphorIconsStyle.duotone), size: 48, color: Colors.grey),
          const Gap(16),
          Text('$title Coming Soon', style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ForYouTab extends ConsumerStatefulWidget {
  const _ForYouTab();

  @override
  ConsumerState<_ForYouTab> createState() => _ForYouTabState();
}

class _ForYouTabState extends ConsumerState<_ForYouTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final microCommunitiesAsync = ref.watch(microCommunitiesProvider);
    final feedAsync = ref.watch(feedProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.refresh(microCommunitiesProvider);
        await ref.read(feedProvider.notifier).refresh();
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Micro-Communities Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Micro-Communities', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      TextButton(onPressed: () {}, child: const Text('See All')),
                    ],
                  ),
                ),
                SizedBox(
                  height: 140,
                  child: microCommunitiesAsync.when(
                    data: (communities) {
                      if (communities.isEmpty) return const Center(child: Text('No communities found'));
                      return ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: communities.length,
                        itemBuilder: (context, index) {
                          final community = communities[index];
                          return _MicroCommunityCard(
                            name: community.name,
                            members: community.members,
                            image: community.imageUrl,
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, s) => Center(child: Text('Error: $e')),
                  ),
                ),
                const Divider(height: 16),
                
                // Feed Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Latest Discussions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const Gap(8),
              ]),
            ),
          ),
          
          // Feed List
          feedAsync.when(
            data: (posts) {
              if (posts.isEmpty) {
                return const SliverToBoxAdapter(child: Center(child: Text('No posts yet')));
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = posts[index];
                    return _FeedPostCard(
                      avatarUrl: post.avatarUrl,
                      userName: post.userName,
                      timeAgo: post.timeAgo,
                      title: post.title,
                      content: post.content,
                      likes: post.likes,
                      comments: post.comments,
                      isAlert: post.isAlert,
                      isOfficial: post.isOfficial,
                      hasImage: post.hasImage,
                      imageUrl: post.imageUrl,
                    );
                  },
                  childCount: posts.length,
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))),
            error: (e, s) => SliverToBoxAdapter(child: Center(child: Text('Error loading feed: $e'))),
          ),
          
          // Bottom padding
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }
}

class _MicroCommunityCard extends StatelessWidget {
  final String name;
  final String members;
  final String image;

  const _MicroCommunityCard({required this.name, required this.members, required this.image});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: image.isNotEmpty
                  ? Image.network(
                      image,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      cacheWidth: 280,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      },
                      errorBuilder: (c, e, s) => Container(color: Colors.grey[300]),
                    )
                  : Container(color: Colors.grey[300]),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('$members members', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  final String avatarUrl;
  final String userName;
  final String timeAgo;
  final String title;
  final String content;
  final int likes;
  final int comments;
  final bool isAlert;
  final bool isOfficial;
  final bool hasImage;
  final String? imageUrl;

  const _FeedPostCard({
    required this.avatarUrl,
    required this.userName,
    required this.timeAgo,
    required this.title,
    required this.content,
    required this.likes,
    required this.comments,
    this.isAlert = false,
    this.isOfficial = false,
    this.hasImage = false,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                  onBackgroundImageError: (e, s) {},
                  child: const Icon(Icons.person, size: 16),
                ),
                const Gap(8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(userName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          if (isOfficial) ...[
                            const Gap(4),
                            Icon(Icons.verified, size: 14, color: theme.colorScheme.primary),
                          ]
                        ],
                      ),
                      Text(timeAgo, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (isAlert)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, size: 14, color: theme.colorScheme.error),
                        const Gap(4),
                        Text('Alert', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
                      ],
                    ),
                  ),
              ],
            ),
            const Gap(12),
            
            // Content
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Gap(4),
            Text(content, style: theme.textTheme.bodyMedium),
            
            if (hasImage && imageUrl != null && imageUrl!.isNotEmpty) ...[
              const Gap(12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl!, 
                  width: double.infinity, 
                  height: 180, 
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 180,
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    color: Colors.grey[300],
                    child: const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.grey)),
                  ),
                ),
              ),
            ],
            
            const Gap(12),
            const Divider(height: 1),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(context, PhosphorIcons.thumbsUp(), '$likes'),
                _buildActionButton(context, PhosphorIcons.chatCircle(), '$comments'),
                _buildActionButton(context, PhosphorIcons.shareNetwork(), 'Share'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const Gap(6),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
