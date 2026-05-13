import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../charger_along_route_model.dart';

class ChargerDetailsSheet extends StatelessWidget {
  final ChargerAlongRoute charger;
  final VoidCallback? onOpenInMaps;

  const ChargerDetailsSheet({
    Key? key,
    required this.charger,
    this.onOpenInMaps,
  }) : super(key: key);

  Color get typeColor {
    switch (charger.chargerType) {
      case 'optimal':
        return Colors.green;
      case 'alternative':
        return Colors.blue;
      case 'far':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String get typeBadgeLabel {
    switch (charger.chargerType) {
      case 'optimal':
        return 'On Recommended Route';
      case 'alternative':
        return 'Nearby Alternative';
      case 'far':
        return 'Far from Route';
      default:
        return charger.chargerType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      maxChildSize: 0.9,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with charger name and type
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: typeColor.withOpacity(0.2),
                      border: Border.all(color: typeColor, width: 2),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.ev_station,
                        color: typeColor,
                        size: 24,
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          charger.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Gap(4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            typeBadgeLabel,
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const Gap(16),

              // Distance from origin
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Distance from Origin',
                value:
                    '${charger.distanceFromOriginKm.toStringAsFixed(1)} km',
              ),

              const Gap(8),

              // Address
              if (charger.address != null)
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Address',
                  value: charger.address!,
                  multiline: true,
                ),

              if (charger.address != null) const Gap(8),

              // Provider
              if (charger.provider != null)
                _InfoRow(
                  icon: Icons.business_outlined,
                  label: 'Provider',
                  value: charger.provider!,
                ),

              if (charger.provider != null) const Gap(8),

              // Power rating
              if (charger.powerKw != null)
                _InfoRow(
                  icon: Icons.bolt_outlined,
                  label: 'Power Rating',
                  value: '${charger.powerKw!.toStringAsFixed(0)} kW',
                ),

              if (charger.powerKw != null) const Gap(8),

              // Connector types
              if (charger.connectorTypes.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.cable_outlined,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const Gap(12),
                        Text(
                          'Connectors',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: charger.connectorTypes
                          .map(
                            (connector) => Chip(
                              label: Text(connector),
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              labelStyle: theme.textTheme.labelSmall,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),

              const Gap(16),

              // Open in Maps button
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: onOpenInMaps,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined,
                          color: theme.colorScheme.primary),
                      const Gap(8),
                      const Text('Open in Maps'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool multiline;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment:
          multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const Gap(12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(4),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
                maxLines: multiline ? null : 1,
                overflow:
                    multiline ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
