import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../charger_along_route_model.dart';

class ChargersList extends StatelessWidget {
  final List<ChargerAlongRoute> chargers;
  final bool showOnlyOptimal;
  final Function(ChargerAlongRoute)? onChargerTap;

  const ChargersList({
    Key? key,
    required this.chargers,
    this.showOnlyOptimal = false,
    this.onChargerTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final displayChargers = showOnlyOptimal
        ? chargers.where((c) => c.isOptimal).toList()
        : chargers;

    if (displayChargers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No chargers found along this route',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: displayChargers.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final charger = displayChargers[index];
        return ChargerListTile(
          charger: charger,
          onTap: () => onChargerTap?.call(charger),
        );
      },
    );
  }
}

/// Single charger list tile
class ChargerListTile extends StatelessWidget {
  final ChargerAlongRoute charger;
  final VoidCallback? onTap;

  const ChargerListTile({
    Key? key,
    required this.charger,
    this.onTap,
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
        return 'On Route';
      case 'alternative':
        return 'Nearby';
      case 'far':
        return 'Far';
      default:
        return charger.chargerType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: typeColor.withOpacity(0.2),
          border: Border.all(color: typeColor, width: 1.5),
        ),
        child: Center(
          child: Icon(
            Icons.ev_station,
            color: typeColor,
            size: 18,
          ),
        ),
      ),
      title: Text(
        charger.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(4),
          if (charger.address != null)
            Text(
              charger.address!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Gap(4),
          Row(
            children: [
              Chip(
                label: Text(typeBadgeLabel),
                backgroundColor: typeColor.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: typeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
              const Gap(8),
              if (charger.provider != null)
                Chip(
                  label: Text(charger.provider!),
                  backgroundColor: Colors.grey.withOpacity(0.2),
                  labelStyle: const TextStyle(
                    fontSize: 12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                ),
            ],
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${charger.distanceFromOriginKm.toStringAsFixed(1)} km',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (charger.powerKw != null)
            Text(
              '${charger.powerKw!.toStringAsFixed(0)}kW',
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

/// Summary header for chargers section
class ChargersSummaryHeader extends StatelessWidget {
  final int totalChargers;
  final int optimalChargers;
  final int alternativeChargers;

  const ChargersSummaryHeader({
    Key? key,
    required this.totalChargers,
    required this.optimalChargers,
    required this.alternativeChargers,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Chargers',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Gap(4),
              Row(
                children: [
                  // Optimal badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🟢 $optimalChargers on route',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Gap(8),
                  // Alternative badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '🔵 $alternativeChargers nearby',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Text(
            'Total: $totalChargers',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
