import 'package:flutter/foundation.dart';

import '../../core/backend_service.dart';
import '../authentication/auth_service.dart';

class ChatService {
  final _authService = AuthService();

  Future<List<dynamic>> getConversation(
    String userId,
    String otherUserId,
  ) async {
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/chat/messages/$userId/$otherUserId',
        headers: {'Authorization': 'Bearer $token'},
      );
      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching conversation: $e');
      return [];
    }
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    final token = _authService.getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to send messages.');
    }

    try {
      await BackendService.post(
        '/api/chat/send',
        body: {
          'sender_id': senderId,
          'receiver_id': receiverId,
          'content': content,
        },
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }
}
