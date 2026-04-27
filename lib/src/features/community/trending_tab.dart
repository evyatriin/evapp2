import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gap/gap.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'news_model.dart';
import 'news_service.dart';

class TrendingTab extends StatefulWidget {
  const TrendingTab({super.key});

  @override
  State<TrendingTab> createState() => _TrendingTabState();
}

class _TrendingTabState extends State<TrendingTab> {
  final _newsService = NewsService();
  String? _selectedCategory;
  
  final Map<String, String> _categories = {
    'all': 'All',
    'vehicles': 'Vehicles',
    'policy': 'Policy',
    'charging': 'Charging',
    'industry': 'Industry',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Category Filter Chips
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _categories.entries.map((entry) {
              final isSelected = _selectedCategory == entry.key || 
                                (_selectedCategory == null && entry.key == 'all');
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(entry.value),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedCategory = entry.key == 'all' ? null : entry.key;
                    });
                  },
                  selectedColor: theme.colorScheme.primaryContainer,
                  checkmarkColor: theme.colorScheme.primary,
                ),
              );
            }).toList(),
          ),
        ),

        // News List
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: FutureBuilder<List<NewsArticle>>(
              future: _newsService.getNews(category: _selectedCategory),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _TrendingStateCard(
                    icon: PhosphorIcons.newspaper(PhosphorIconsStyle.duotone),
                    title: 'Loading latest updates',
                    subtitle: 'Pulling EV stories and industry signals for you.',
                    child: const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _TrendingStateCard(
                    icon: PhosphorIcons.warning(PhosphorIconsStyle.duotone),
                    title: 'Couldn\'t load updates',
                    subtitle: 'Pull to retry and refresh the latest EV articles.',
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _TrendingStateCard(
                    icon: PhosphorIcons.newspaper(PhosphorIconsStyle.duotone),
                    title: 'No stories in this category',
                    subtitle: 'Try another filter or refresh for newer coverage.',
                  );
                }

                final news = snapshot.data!;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: news.length,
                  itemBuilder: (context, index) {
                    return _NewsCard(article: news[index]);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  final NewsArticle article;

  const _NewsCard({required this.article});

  Future<void> _launchUrl() async {
    final uri = Uri.parse(article.sourceUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch ${article.sourceUrl}');
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryColor = switch (article.category) {
      'vehicles' => theme.colorScheme.primary,
      'policy' => theme.colorScheme.secondary,
      'charging' => theme.colorScheme.tertiary,
      'industry' => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: article.isFeatured ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: article.isFeatured 
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: _launchUrl,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (article.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  article.imageUrl!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      PhosphorIcons.image(PhosphorIconsStyle.duotone),
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Badge & Featured
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          article.category.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: categoryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (article.isFeatured) ...[
                        const Gap(8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), 
                                   size: 12, color: theme.colorScheme.primary),
                              const Gap(4),
                              Text(
                                'FEATURED',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  const Gap(12),

                  // Title
                  Text(
                    article.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const Gap(8),

                  // Summary
                  Text(
                    article.summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Gap(12),

                  // Source & Time
                  Row(
                    children: [
                      Icon(PhosphorIcons.newspaper(PhosphorIconsStyle.duotone), 
                           size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const Gap(4),
                      Text(
                        article.sourceName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Gap(8),
                      Text(
                        '•',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Gap(8),
                      Icon(PhosphorIcons.clock(PhosphorIconsStyle.duotone), 
                           size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const Gap(4),
                      Text(
                        timeago.format(article.publishedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Icon(PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.duotone), 
                           size: 20, color: theme.colorScheme.primary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendingStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? child;

  const _TrendingStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: theme.colorScheme.primary),
              const Gap(12),
              Text(title, style: theme.textTheme.titleMedium),
              const Gap(6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (child != null) child!,
            ],
          ),
        ),
      ),
    );
  }
}
