import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/backend_service.dart';

class Badge {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String requirementType;
  final int requirementValue;

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.requirementType,
    required this.requirementValue,
  });

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      icon: json['icon'],
      requirementType: json['requirement_type'],
      requirementValue: json['requirement_value'],
    );
  }
}

class LeaderboardEntry {
  final String userId;
  final String name;
  final String? profileImageUrl;
  final int totalPoints;
  final int currentStreak;
  final int badgeCount;
  final int rank;

  LeaderboardEntry({
    required this.userId,
    required this.name,
    this.profileImageUrl,
    required this.totalPoints,
    required this.currentStreak,
    required this.badgeCount,
    required this.rank,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      userId: json['user_id'],
      name: json['name'],
      profileImageUrl: json['profile_image_url'],
      totalPoints: json['total_points'],
      currentStreak: json['current_streak'],
      badgeCount: json['badge_count'],
      rank: json['rank'],
    );
  }
}

class GamificationService {
  static const String _baseUrl = '${BackendService.baseUrl}/api/gamification';

  Future<List<LeaderboardEntry>> getLeaderboard() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/leaderboard'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => LeaderboardEntry.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load leaderboard');
      }
    } catch (e) {
      print('Error fetching leaderboard: $e');
      return [];
    }
  }

  Future<List<Badge>> getBadges() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/badges'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Badge.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load badges');
      }
    } catch (e) {
      print('Error fetching badges: $e');
      return [];
    }
  }

  Future<List<Badge>> getUserBadges(String userId) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/badges/user/$userId'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Badge.fromJson(json['badge'])).toList();
      } else {
        throw Exception('Failed to load user badges');
      }
    } catch (e) {
      print('Error fetching user badges: $e');
      return [];
    }
  }
  
  Future<void> updateStreak(String userId) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/streak/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId}),
      );
    } catch (e) {
      print('Error updating streak: $e');
    }
  }
}
