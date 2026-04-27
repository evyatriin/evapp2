import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'content_service.dart';

class ResourcesTab extends StatefulWidget {
  const ResourcesTab({super.key});

  @override
  State<ResourcesTab> createState() => _ResourcesTabState();
}

class _ResourcesTabState extends State<ResourcesTab> {
  final _contentService = ContentService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<ResourceSectionModel>>(
      future: _contentService.getResources(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _ResourcesState(
            icon: PhosphorIcons.bookOpenText(PhosphorIconsStyle.duotone),
            title: 'Loading practical EV guides',
            subtitle: 'Pulling charging help, ownership tips, and emergency contacts.',
            child: const CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return _ResourcesState(
            icon: PhosphorIcons.warningCircle(PhosphorIconsStyle.duotone),
            title: 'Guides are unavailable right now',
            subtitle: 'We could not load the latest help content. Pull to retry in a moment.',
            child: FilledButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          );
        }

        final sections = snapshot.data ?? const <ResourceSectionModel>[];
        if (sections.isEmpty) {
          return _ResourcesState(
            icon: PhosphorIcons.bookmarksSimple(PhosphorIconsStyle.duotone),
            title: 'No guides published yet',
            subtitle: 'This area will fill with charging help, policy tips, and emergency resources.',
            child: const SizedBox.shrink(),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Practical EV Guides',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Gap(8),
            Text(
              'Charging help, ownership advice, and emergency support you can act on quickly.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Gap(24),
            ...sections.map(
              (section) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ResourceSection(section: section),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResourcesState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _ResourcesState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 420,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 34, color: theme.colorScheme.primary),
                  ),
                  const Gap(18),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(18),
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResourceSection extends StatelessWidget {
  final ResourceSectionModel section;

  const _ResourceSection({required this.section});

  Color _toneColor(ThemeData theme) {
    switch (section.tone) {
      case 'amber':
        return theme.colorScheme.tertiary;
      case 'blue':
        return theme.colorScheme.secondary;
      case 'green':
        return theme.colorScheme.primary;
      case 'red':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.primary;
    }
  }

  IconData _iconData() {
    switch (section.icon) {
      case 'lightning':
        return PhosphorIcons.lightning(PhosphorIconsStyle.duotone);
      case 'car':
        return PhosphorIcons.car(PhosphorIconsStyle.duotone);
      case 'bank':
        return PhosphorIcons.bank(PhosphorIconsStyle.duotone);
      case 'phone':
        return PhosphorIcons.phone(PhosphorIconsStyle.duotone);
      default:
        return PhosphorIcons.bookOpenText(PhosphorIconsStyle.duotone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _toneColor(theme);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_iconData(), color: color, size: 24),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (section.description.isNotEmpty) ...[
                        const Gap(2),
                        Text(
                          section.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const Gap(16),
            ...section.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ResourceItem(item: item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceItem extends StatelessWidget {
  final ResourceItemModel item;

  const _ResourceItem({required this.item});

  Future<void> _launchUrl() async {
    final uri = Uri.parse(item.url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch ${item.url}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: _launchUrl,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    item.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.duotone),
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
