import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'community_service.dart';
import 'community_models.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community Hub'),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => context.push('/sos'),
                icon: const Icon(Icons.sos, size: 18),
                label: const Text('SOS'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'For You'),
              Tab(text: 'My Communities'),
              Tab(text: 'Trending'),
              Tab(text: 'Resources'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildForYouTab(context),
            _buildPlaceholderTab(context, 'My Communities'),
            _buildPlaceholderTab(context, 'Trending'),
            _buildPlaceholderTab(context, 'Resources'),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildForYouTab(BuildContext context) {
    final communityService = CommunityService();

    return RefreshIndicator(
      onRefresh: () async {
        // In a real app, this would trigger a provider refresh
        // For now, setState to rebuild FutureBuilder would be needed if we weren't creating service in build
        // Since we are creating service here, we might need a stateful widget for proper refresh
        // But for MVP this is okay to just trigger UI update
        (context as Element).markNeedsBuild(); 
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
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
            child: FutureBuilder<List<MicroCommunity>>(
              future: communityService.getMicroCommunities(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No communities found'));
                }
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final community = snapshot.data![index];
                    return _MicroCommunityCard(
                      name: community.name,
                      members: community.members,
                      image: community.imageUrl,
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 32),
          
          // Feed Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Latest Discussions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const Gap(8),
          FutureBuilder<List<FeedPost>>(
            future: communityService.getFeed(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('No posts yet'));
              }
              return Column(
                children: snapshot.data!.map((post) => _FeedPostCard(
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
                )).toList(),
              );
            },
          ),
        ],
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
              child: Image.network(
                image,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) => Container(color: Colors.grey[300]),
              ),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: NetworkImage(avatarUrl),
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
            
            if (hasImage && imageUrl != null) ...[
              const Gap(12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(imageUrl!, width: double.infinity, height: 180, fit: BoxFit.cover),
              ),
            ],
            
            const Gap(16),
            const Divider(),
            
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
