class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
  });

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? profileImageUrl,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
    );
  }

  // JSON serialization
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      profileImageUrl: json['profile_image_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profile_image_url': profileImageUrl,
    };
  }
}
