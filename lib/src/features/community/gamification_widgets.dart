import 'package:flutter/material.dart' hide Badge;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:gap/gap.dart';
import 'gamification_service.dart';

class PointsBadge extends StatelessWidget {
  final int points;
  final bool compact;
  final Color? color;

  const PointsBadge({
    super.key,
    required this.points,
    this.compact = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = color ?? theme.colorScheme.primary;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), size: 14, color: badgeColor),
            const Gap(4),
            Text(
              '$points',
              style: theme.textTheme.labelSmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [badgeColor, badgeColor.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.star(PhosphorIconsStyle.fill), size: 16, color: Colors.white),
          const Gap(6),
          Text(
            '$points Points',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class StreakWidget extends StatelessWidget {
  final int streak;
  final bool compact;

  const StreakWidget({
    super.key,
    required this.streak,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fireColor = Colors.orange;

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.fire(PhosphorIconsStyle.fill), size: 16, color: fireColor),
          const Gap(2),
          Text(
            '$streak',
            style: theme.textTheme.labelMedium?.copyWith(
              color: fireColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: fireColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fireColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.fire(PhosphorIconsStyle.fill), size: 20, color: fireColor),
          const Gap(8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$streak Day Streak',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: fireColor,
                ),
              ),
              Text(
                'Keep it up!',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BadgeWidget extends StatelessWidget {
  final Badge badge;
  final bool isLocked;
  final double size;

  const BadgeWidget({
    super.key,
    required this.badge,
    this.isLocked = false,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Tooltip(
      message: '${badge.name}\n${badge.description}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLocked ? Colors.grey[200] : theme.colorScheme.primaryContainer,
              border: Border.all(
                color: isLocked ? Colors.grey[400]! : theme.colorScheme.primary,
                width: 2,
              ),
            ),
            child: Center(
              child: Icon(
                _getIconData(badge.icon),
                size: size * 0.5,
                color: isLocked ? Colors.grey[400] : theme.colorScheme.primary,
              ),
            ),
          ),
          const Gap(8),
          Text(
            badge.name,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isLocked ? Colors.grey : theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'check_circle':
        return PhosphorIcons.checkCircle(PhosphorIconsStyle.duotone);
      case 'map':
        return PhosphorIcons.mapTrifold(PhosphorIconsStyle.duotone);
      case 'local_fire_department':
        return PhosphorIcons.fire(PhosphorIconsStyle.duotone);
      default:
        return PhosphorIcons.trophy(PhosphorIconsStyle.duotone);
    }
  }
}
