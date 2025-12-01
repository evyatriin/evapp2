class MicroCommunity {
  final String id;
  final String name;
  final String members;
  final String imageUrl;

  MicroCommunity({
    required this.id,
    required this.name,
    required this.members,
    required this.imageUrl,
  });

  factory MicroCommunity.fromJson(Map<String, dynamic> json) {
    return MicroCommunity(
      id: json['id'],
      name: json['name'],
      members: json['members'],
      imageUrl: json['imageUrl'],
    );
  }
}

class FeedPost {
  final String id;
  final String avatarUrl;
  final String userName;
  final String timeAgo;
  final String title;
  final String content;
  final int likes;
  final int comments;
  final bool isAlert;
  final bool isOfficial;
  final bool hasImage;
  final String? imageUrl;

  FeedPost({
    required this.id,
    required this.avatarUrl,
    required this.userName,
    required this.timeAgo,
    required this.title,
    required this.content,
    required this.likes,
    required this.comments,
    this.isAlert = false,
    this.isOfficial = false,
    this.hasImage = false,
    this.imageUrl,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    return FeedPost(
      id: json['id'],
      avatarUrl: json['avatarUrl'],
      userName: json['userName'],
      timeAgo: json['timeAgo'],
      title: json['title'],
      content: json['content'],
      likes: json['likes'],
      comments: json['comments'],
      isAlert: json['isAlert'] ?? false,
      isOfficial: json['isOfficial'] ?? false,
      hasImage: json['hasImage'] ?? false,
      imageUrl: json['imageUrl'],
    );
  }
}
