import '../../core/backend_service.dart';

class ResourceSectionModel {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String tone;
  final List<ResourceItemModel> items;

  const ResourceSectionModel({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.tone,
    required this.items,
  });

  factory ResourceSectionModel.fromJson(Map<String, dynamic> json) {
    return ResourceSectionModel(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      icon: (json['icon'] as String?) ?? 'book-open',
      tone: (json['tone'] as String?) ?? 'primary',
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .map((item) => ResourceItemModel.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ResourceItemModel {
  final String id;
  final String title;
  final String subtitle;
  final String url;

  const ResourceItemModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  factory ResourceItemModel.fromJson(Map<String, dynamic> json) {
    return ResourceItemModel(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: (json['subtitle'] as String?) ?? '',
      url: json['url'] as String,
    );
  }
}

class ContentService {
  Future<List<ResourceSectionModel>> getResources() async {
    final response = await BackendService.get('/api/content/resources');
    final resources = response as List<dynamic>;
    return resources
        .map(
          (item) => ResourceSectionModel.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }
}
