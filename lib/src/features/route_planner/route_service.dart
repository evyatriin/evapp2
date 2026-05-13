import 'package:flutter/foundation.dart';

import '../../core/backend_service.dart';
import 'saved_route_model.dart';
import '../authentication/auth_service.dart';

class RouteService {
  final _authService = AuthService();

  /// Get current user ID
  String? get _userId => _authService.currentUserId;

  /// Fetch all saved routes for the current user
  Future<List<SavedRoute>> getSavedRoutes() async {
    final userId = _userId;
    if (userId == null) return [];
    final token = _authService.getAuthToken();
    if (token == null) return [];

    try {
      final response = await BackendService.get(
        '/api/routes/',
        queryParams: {'user_id': userId},
        headers: {'Authorization': 'Bearer $token'},
      );
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => SavedRoute.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching saved routes: $e');
      return [];
    }
  }

  /// Save a new route
  Future<SavedRoute?> saveRoute(SavedRoute route) async {
    final token = _authService.getAuthToken();
    if (token == null) return null;

    try {
      // Extract elevation data from route model if available
      final elevationGainM = route.routeData.elevationProfile?.elevationGainM;
      final elevationLossM = route.routeData.elevationProfile?.elevationLossM;

      // Create route with elevation data for storage
      final routeWithElevation = route.copyWith(
        elevationGainM: elevationGainM,
        elevationLossM: elevationLossM,
      );

      final response = await BackendService.post(
        '/api/routes/',
        body: routeWithElevation.toJson(),
        headers: {'Authorization': 'Bearer $token'},
      );
      return SavedRoute.fromJson(response);
    } catch (e) {
      debugPrint('Error saving route: $e');
      return null;
    }
  }

  /// Delete a saved route
  Future<bool> deleteRoute(String routeId) async {
    final token = _authService.getAuthToken();
    if (token == null) return false;

    try {
      await BackendService.delete(
        '/api/routes/$routeId',
        headers: {'Authorization': 'Bearer $token'},
      );
      return true;
    } catch (e) {
      debugPrint('Error deleting route: $e');
      return false;
    }
  }

  /// Toggle favorite status
  Future<bool> toggleFavorite(String routeId, bool isFavorite) async {
    final token = _authService.getAuthToken();
    if (token == null) return false;

    try {
      await BackendService.post(
        '/api/routes/$routeId/favorite',
        body: {'is_favorite': isFavorite},
        headers: {'Authorization': 'Bearer $token'},
      );
      return true;
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      return false;
    }
  }
}
