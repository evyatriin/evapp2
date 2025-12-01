class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;
  final bool isPhoneVerified;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
    this.isPhoneVerified = false,
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? profileImageUrl,
    bool? isPhoneVerified,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
    );
  }

  // JSON serialization
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      profileImageUrl: json['profile_image_url'] as String?,
      isPhoneVerified: json['is_phone_verified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profile_image_url': profileImageUrl,
      'is_phone_verified': isPhoneVerified,
    };
  }
}
