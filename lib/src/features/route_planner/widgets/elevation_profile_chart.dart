import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:fl_chart/fl_chart.dart';
import '../route_model.dart';

class ElevationProfileChart extends StatefulWidget {
  final ElevationProfile elevationProfile;
  final List<RouteStop> stops;

  const ElevationProfileChart({
    super.key,
    required this.elevationProfile,
    required this.stops,
  });

  @override
  State<ElevationProfileChart> createState() => _ElevationProfileChartState();
}

class _ElevationProfileChartState extends State<ElevationProfileChart> {
  double? _selectedDistance;
  double? _selectedElevation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = widget.elevationProfile.points;

    if (points.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No elevation data available',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    // Find charging stops with their distances
    final chargingStopsWithDistance =
        widget.stops
            .where(
              (s) =>
                  s.type == StopType.charging && s.distanceFromOriginKm != null,
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chart
        SizedBox(
          height: 220,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final localPosition = details.localPosition;
                  final chartWidth = box.size.width - 60; // Account for margins
                  final relativeX = (localPosition.dx - 40) / chartWidth;
                  _selectedDistance =
                      relativeX * (points.last.distanceFromOriginKm);
                }
              });
            },
            onHorizontalDragEnd: (_) {
              setState(() {
                _selectedDistance = null;
                _selectedElevation = null;
              });
            },
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: points.last.distanceFromOriginKm,
                minY:
                    widget.elevationProfile.minElevationM -
                    ((widget.elevationProfile.maxElevationM -
                            widget.elevationProfile.minElevationM) *
                        0.1),
                maxY:
                    widget.elevationProfile.maxElevationM +
                    ((widget.elevationProfile.maxElevationM -
                            widget.elevationProfile.minElevationM) *
                        0.1),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _getGridInterval(
                    widget.elevationProfile.maxElevationM -
                        widget.elevationProfile.minElevationM,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: _getAxisInterval(
                        points.last.distanceFromOriginKm,
                      ),
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()} km',
                          style: theme.textTheme.labelSmall,
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: _getGridInterval(
                        widget.elevationProfile.maxElevationM -
                            widget.elevationProfile.minElevationM,
                      ),
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()} m',
                          style: theme.textTheme.labelSmall,
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                    left: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots:
                        points
                            .map(
                              (p) =>
                                  FlSpot(p.distanceFromOriginKm, p.elevationM),
                            )
                            .toList(),
                    isCurved: true,
                    color: theme.colorScheme.primary,
                    barWidth: 2,
                    belowBarData: BarAreaData(
                      show: true,
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                    dotData: const FlDotData(show: false),
                  ),
                ],
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    // Selected position line
                    if (_selectedDistance != null)
                      VerticalLine(
                        x: _selectedDistance!,
                        color: theme.colorScheme.tertiary.withValues(
                          alpha: 0.5,
                        ),
                        strokeWidth: 2,
                      ),
                    // Charging stops vertical lines
                    ...chargingStopsWithDistance.map(
                      (stop) => VerticalLine(
                        x: stop.distanceFromOriginKm!,
                        color: theme.colorScheme.tertiaryContainer,
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Gap(12),

        // Stats Row
        if (_selectedDistance != null && _selectedElevation != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    Text(
                      'Distance',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Gap(4),
                    Text(
                      '${_selectedDistance!.toStringAsFixed(1)} km',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      'Elevation',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Gap(4),
                    Text(
                      '${_selectedElevation!.toStringAsFixed(0)} m',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (chargingStopsWithDistance.isNotEmpty)
                  Column(
                    children: [
                      Text(
                        'Charging Stops',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Gap(4),
                      Text(
                        '${chargingStopsWithDistance.length}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          )
        else ...[
          // Summary Stats
          _buildStatRow(
            context,
            '↑ Elevation Gain',
            '${widget.elevationProfile.elevationGainM.toStringAsFixed(0)} m',
          ),
          const Gap(8),
          _buildStatRow(
            context,
            '↓ Elevation Loss',
            '${widget.elevationProfile.elevationLossM.toStringAsFixed(0)} m',
          ),
          const Gap(8),
          _buildStatRow(
            context,
            'Avg. Gradient',
            '${widget.elevationProfile.averageGradientPct.toStringAsFixed(2)}%',
          ),
        ],

        // Legend
        if (chargingStopsWithDistance.isNotEmpty) ...[
          const Gap(12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Gap(6),
                Text(
                  '${chargingStopsWithDistance.length} charging stops marked',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  double _getGridInterval(double range) {
    if (range < 100) return 20;
    if (range < 500) return 50;
    if (range < 1000) return 100;
    return 200;
  }

  double _getAxisInterval(double maxDistance) {
    if (maxDistance < 50) return 5;
    if (maxDistance < 200) return 25;
    if (maxDistance < 500) return 50;
    return 100;
  }
}
