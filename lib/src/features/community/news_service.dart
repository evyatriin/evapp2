import '../../core/backend_service.dart';
import 'news_model.dart';

class NewsService {
  Future<List<NewsArticle>> getNews({
    String? category,
    bool featuredOnly = false,
  }) async {
    final response = await BackendService.get(
      '/api/news',
      queryParams: {
        if (category != null) 'category': category,
        if (featuredOnly) 'featured_only': 'true',
        'limit': '20',
      },
    );

    final news = response as List<dynamic>;
    return news
        .map(
          (item) => NewsArticle.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }
}
