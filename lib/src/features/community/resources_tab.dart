import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gap/gap.dart';

class ResourcesTab extends StatelessWidget {
  const ResourcesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'EV Resources',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Gap(8),
        Text(
          'Everything you need to know about EV ownership',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        const Gap(24),

        // Charging Guides
        _ResourceSection(
          icon: PhosphorIcons.lightning(PhosphorIconsStyle.duotone),
          title: 'Charging Guides',
          color: Colors.amber,
          items: const [
            _ResourceItem(
              title: 'Understanding Connector Types',
              subtitle: 'CCS, CHAdeMO, Type 2 explained',
              url: 'https://evyatra.com/charging-connectors',
            ),
            _ResourceItem(
              title: 'Charging Etiquette',
              subtitle: 'Best practices at public chargers',
              url: 'https://evyatra.com/charging-etiquette',
            ),
            _ResourceItem(
              title: 'AC vs DC Charging',
              subtitle: 'Speed differences and when to use',
              url: 'https://evyatra.com/ac-vs-dc',
            ),
          ],
        ),

        const Gap(16),

        // Ownership Tips
        _ResourceSection(
          icon: PhosphorIcons.car(PhosphorIconsStyle.duotone),
          title: 'EV Ownership Tips',
          color: Colors.blue,
          items: const [
            _ResourceItem(
              title: 'Battery Care Guide',
              subtitle: 'Maximize battery life and health',
              url: 'https://evyatra.com/battery-care',
            ),
            _ResourceItem(
              title: 'Range Optimization',
              subtitle: 'Get the most out of every charge',
              url: 'https://evyatra.com/range-tips',
            ),
            _ResourceItem(
              title: 'Seasonal Driving Tips',
              subtitle: 'Winter and summer best practices',
              url: 'https://evyatra.com/seasonal-tips',
            ),
          ],
        ),

        const Gap(16),

        // Government Schemes
        _ResourceSection(
          icon: PhosphorIcons.bank(PhosphorIconsStyle.duotone),
          title: 'Government Schemes',
          color: Colors.green,
          items: const [
            _ResourceItem(
              title: 'FAME II Subsidy',
              subtitle: 'Central government EV incentives',
              url: 'https://fame2.heavyindustries.gov.in/',
            ),
            _ResourceItem(
              title: 'State EV Policies',
              subtitle: 'State-specific benefits and subsidies',
              url: 'https://evyatra.com/state-policies',
            ),
            _ResourceItem(
              title: 'Tax Benefits',
              subtitle: 'Income tax deductions for EV owners',
              url: 'https://evyatra.com/tax-benefits',
            ),
          ],
        ),

        const Gap(16),

        // Emergency Contacts
        _ResourceSection(
          icon: PhosphorIcons.phone(PhosphorIconsStyle.duotone),
          title: 'Emergency Contacts',
          color: Colors.red,
          items: const [
            _ResourceItem(
              title: 'Tata Motors EV Support',
              subtitle: 'Tap to call: 1800-209-7979',
              url: 'tel:18002097979',
            ),
            _ResourceItem(
              title: 'MG Motor Support',
              subtitle: 'Tap to call: 1800-102-4644',
              url: 'tel:18001024644',
            ),
            _ResourceItem(
              title: 'Hyundai EV Helpline',
              subtitle: 'Tap to call: 1800-11-4645',
              url: 'tel:1800114645',
            ),
          ],
        ),

        const Gap(16),

        // Useful Links
        _ResourceSection(
          icon: PhosphorIcons.link(PhosphorIconsStyle.duotone),
          title: 'Useful Links',
          color: Colors.purple,
          items: const [
            _ResourceItem(
              title: 'EV Yatra',
              subtitle: 'Comprehensive EV information portal',
              url: 'https://evyatra.com',
            ),
            _ResourceItem(
              title: 'Charging Station Finder',
              subtitle: 'Find chargers across India',
              url: 'https://evyatra.com/charging-stations',
            ),
            _ResourceItem(
              title: 'EV Forums India',
              subtitle: 'Connect with EV community',
              url: 'https://evyatra.com/forums',
            ),
          ],
        ),
      ],
    );
  }
}

class _ResourceSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<_ResourceItem> items;

  const _ResourceSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                  child: Icon(icon, color: color, size: 24),
                ),
                const Gap(12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Gap(16),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: item,
            )),
          ],
        ),
      ),
    );
  }
}

class _ResourceItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final String url;

  const _ResourceItem({
    required this.title,
    required this.subtitle,
    required this.url,
  });

  Future<void> _launchUrl() async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
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
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Gap(4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
