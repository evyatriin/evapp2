import '../../core/backend_service.dart';

/// Block + report user. Backed by /api/users/block and /api/users/report.
/// Required for Play Store user-generated-content compliance.
class ModerationService {
  Future<void> blockUser({
    required String blockerId,
    required String blockedId,
    required String authToken,
  }) async {
    await BackendService.post(
      '/api/users/block',
      body: {
        'blocker_id': blockerId,
        'blocked_id': blockedId,
      },
      headers: {'Authorization': 'Bearer $authToken'},
    );
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedUserId,
    required String reason,
    String? details,
    required String authToken,
  }) async {
    await BackendService.post(
      '/api/users/report',
      body: {
        'reporter_id': reporterId,
        'reported_user_id': reportedUserId,
        'reason': reason,
        if (details != null && details.isNotEmpty) 'details': details,
      },
      headers: {'Authorization': 'Bearer $authToken'},
    );
  }
}
