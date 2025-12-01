import '../../core/backend_service.dart';
import 'community_models.dart';

class CommunityService {
  Future<List<MicroCommunity>> getMicroCommunities() async {
    try {
      final response = await BackendService.get('/api/community/groups');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => MicroCommunity.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching micro-communities: $e');
      return [];
    }
  }

  Future<List<FeedPost>> getFeed() async {
    try {
      final response = await BackendService.get('/api/community/feed');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => FeedPost.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching feed: $e');
      return [];
    }
  }

  Future<void> likePost(String postId, String userId) async {
    try {
      await BackendService.post('/api/community/posts/$postId/like?user_id=$userId', body: {});
    } catch (e) {
      print('Error liking post: $e');
    }
  }
}
