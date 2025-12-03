class NewsArticle {
  final String id;
  final String title;
  final String summary;
  final String sourceUrl;
  final String sourceName;
  final DateTime publishedAt;
  final String? imageUrl;
  final String category; // 'policy', 'vehicles', 'charging', 'industry'
  final bool isFeatured;

  NewsArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.sourceUrl,
    required this.sourceName,
    required this.publishedAt,
    this.imageUrl,
    required this.category,
    this.isFeatured = false,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['id'],
      title: json['title'],
      summary: json['summary'] ?? '',
      sourceUrl: json['source_url'],
      sourceName: json['source_name'],
      publishedAt: DateTime.parse(json['published_at']),
      imageUrl: json['image_url'],
      category: json['category'],
      isFeatured: json['is_featured'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'source_url': sourceUrl,
      'source_name': sourceName,
      'published_at': publishedAt.toIso8601String(),
      'image_url': imageUrl,
      'category': category,
      'is_featured': isFeatured,
    };
  }
}
