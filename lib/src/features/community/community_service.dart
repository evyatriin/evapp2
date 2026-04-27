import 'package:flutter/foundation.dart';

import '../../core/backend_service.dart';
import '../authentication/auth_service.dart';
import 'community_models.dart';

class CommunityService {
  final _authService = AuthService();

  Future<List<MicroCommunity>> getMicroCommunities() async {
    try {
      final response = await BackendService.get('/api/community/groups');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => MicroCommunity.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching micro-communities: $e');
      return [];
    }
  }

  Future<List<FeedPost>> getFeed({int limit = 10, int offset = 0}) async {
    try {
      final response = await BackendService.get(
        '/api/community/feed?limit=$limit&offset=$offset',
      );
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => FeedPost.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching feed: $e');
      return [];
    }
  }

  Future<void> likePost(String postId, String userId) async {
    final token = _authService.getAuthToken();
    if (token == null) return;

    try {
      await BackendService.post(
        '/api/community/posts/$postId/like?user_id=$userId',
        body: {},
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Error liking post: $e');
    }
  }
}
