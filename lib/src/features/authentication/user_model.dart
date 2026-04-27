class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;
  final String? phoneNumber;
  final bool isPhoneVerified;
  final int points;
  final int streak;
  final List<String> badges;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
    this.phoneNumber,
    this.isPhoneVerified = false,
    this.points = 0,
    this.streak = 0,
    this.badges = const [],
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? profileImageUrl,
    String? phoneNumber,
    bool? isPhoneVerified,
    int? points,
    int? streak,
    List<String>? badges,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      points: points ?? this.points,
      streak: streak ?? this.streak,
      badges: badges ?? this.badges,
    );
  }

  // JSON serialization
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      profileImageUrl: json['profile_image_url'] as String?,
      phoneNumber: json['phone_number'] as String?,
      isPhoneVerified: json['is_phone_verified'] as bool? ?? false,
      points: json['points'] as int? ?? 0,
      streak: json['streak'] as int? ?? 0,
      badges: (json['badges'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profile_image_url': profileImageUrl,
      'phone_number': phoneNumber,
      'is_phone_verified': isPhoneVerified,
      'points': points,
      'streak': streak,
      'badges': badges,
    };
  }
}
