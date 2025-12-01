import '../../core/backend_service.dart';

class ChatService {
  Future<List<dynamic>> getConversation(String userId, String otherUserId) async {
    try {
      final response = await BackendService.get('/api/chat/messages/$userId/$otherUserId');
      return response as List<dynamic>;
    } catch (e) {
      print('Error fetching conversation: $e');
      return [];
    }
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String content,
  }) async {
    try {
      await BackendService.post('/api/chat/send', body: {
        'sender_id': senderId,
        'receiver_id': receiverId,
        'content': content,
      });
    } catch (e) {
      print('Error sending message: $e');
      throw e;
    }
  }
}
