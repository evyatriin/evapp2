import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'community_service.dart';
import 'community_models.dart';

final communityServiceProvider = Provider((ref) => CommunityService());

final microCommunitiesProvider = FutureProvider<List<MicroCommunity>>((ref) async {
  final service = ref.watch(communityServiceProvider);
  return service.getMicroCommunities();
});

final feedProvider = AsyncNotifierProvider<FeedNotifier, List<FeedPost>>(FeedNotifier.new);

class FeedNotifier extends AsyncNotifier<List<FeedPost>> {
  int _offset = 0;
  final int _limit = 10;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  Future<List<FeedPost>> build() async {
    return _loadInitial();
  }

  Future<List<FeedPost>> _loadInitial() async {
    final service = ref.watch(communityServiceProvider);
    _offset = 0;
    _hasMore = true;
    _isLoadingMore = false;
    
    final posts = await service.getFeed(limit: _limit, offset: _offset);
    _offset += posts.length;
    if (posts.length < _limit) _hasMore = false;
    
    return posts;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || state.value == null) return;

    _isLoadingMore = true;
    try {
      final service = ref.read(communityServiceProvider);
      final newPosts = await service.getFeed(limit: _limit, offset: _offset);
      
      if (newPosts.isEmpty) {
        _hasMore = false;
      } else {
        _offset += newPosts.length;
        if (newPosts.length < _limit) _hasMore = false;
        
        final currentPosts = state.value ?? [];
        state = AsyncValue.data([...currentPosts, ...newPosts]);
      }
    } catch (e) {
      print('Error loading more posts: $e');
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
