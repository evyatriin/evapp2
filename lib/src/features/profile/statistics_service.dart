import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/backend_service.dart';

part 'statistics_service.g.dart';

class UserStatistics {
  final double totalKm;
  final double totalKwhCharged;
  final double co2SavedKg;
  final double moneySaved;
  final int totalCheckIns;
  final int totalTrips;

  const UserStatistics({
    required this.totalKm,
    required this.totalKwhCharged,
    required this.co2SavedKg,
    required this.moneySaved,
    required this.totalCheckIns,
    required this.totalTrips,
  });

  factory UserStatistics.empty() => const UserStatistics(
    totalKm: 0,
    totalKwhCharged: 0,
    co2SavedKg: 0,
    moneySaved: 0,
    totalCheckIns: 0,
    totalTrips: 0,
  );

  factory UserStatistics.fromJson(Map<String, dynamic> json) {
    return UserStatistics(
      totalKm: (json['total_km'] as num?)?.toDouble() ?? 0,
      totalKwhCharged: (json['total_kwh_charged'] as num?)?.toDouble() ?? 0,
      co2SavedKg: (json['co2_saved_kg'] as num?)?.toDouble() ?? 0,
      moneySaved: (json['money_saved'] as num?)?.toDouble() ?? 0,
      totalCheckIns: json['total_check_ins'] as int? ?? 0,
      totalTrips: json['total_trips'] as int? ?? 0,
    );
  }
}

class StatisticsService {
  Future<UserStatistics> getUserStatistics(String userId) async {
    try {
      final response = await BackendService.get('/api/users/$userId/statistics');
      return UserStatistics.fromJson(response);
    } catch (e) {
      print('Error fetching statistics: $e');
      // Return empty stats on error
      return UserStatistics.empty();
    }
  }
}

@riverpod
Future<UserStatistics> userStatistics(Ref ref, String userId) async {
  if (userId.isEmpty) {
    return UserStatistics.empty();
  }
  final service = StatisticsService();
  return service.getUserStatistics(userId);
}
