import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import 'obd_controller.dart';
import 'obd_history_service.dart';
import 'obd_models.dart';

class ObdAnalyticsScreen extends ConsumerWidget {
  const ObdAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(obdSessionControllerProvider);
    final telemetry = session.telemetry;
    final analytics = session.analytics;
    final historyAsync = ref.watch(obdHistoryEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OBD Analytics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connection',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Text('Status: ${_statusLabel(session.stage)}'),
                  Text(
                    'Adapter: ${session.selectedDevice?.name ?? 'Not connected'}',
                  ),
                  const Gap(8),
                  Text(session.statusMessage),
                ],
              ),
            ),
          ),
          const Gap(12),
          historyAsync.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Loading saved OBD history...'),
              ),
            ),
            error: (error, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load saved history: $error'),
              ),
            ),
            data: (entries) {
              final historyService = ObdHistoryService();
              final monthly = historyService.aggregateForCurrentMonth(entries);
              final yearly = historyService.aggregateForCurrentYear(entries);
              final byMonth = historyService.aggregateByMonth(entries);

              return Column(
                children: [
                  _AggregateCard(
                    title: 'This Month',
                    aggregate: monthly,
                  ),
                  const Gap(12),
                  _AggregateCard(
                    title: 'This Year',
                    aggregate: yearly,
                  ),
                  const Gap(12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Month by Month',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(12),
                          if (byMonth.isEmpty)
                            const Text('No saved OBD history yet.')
                          else
                            ...byMonth.take(12).map(
                              (aggregate) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        aggregate.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Text(
                                      '${aggregate.totalDistanceKm.toStringAsFixed(1)} km',
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      '${aggregate.averageEfficiencyScore.toStringAsFixed(0)}%',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recent Sessions',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(12),
                          if (entries.isEmpty)
                            const Text('No saved sessions yet.')
                          else
                            ...entries.take(10).map(
                              (entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.deviceName ?? 'Unknown adapter',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const Gap(4),
                                    Text(
                                      '${DateFormat('dd MMM yyyy, hh:mm a').format(entry.updatedAt)} • ${entry.tripDistanceKm.toStringAsFixed(1)} km',
                                    ),
                                    Text(
                                      'Efficiency ${entry.efficiencyScore.toStringAsFixed(0)}% • Smooth ${entry.smoothDrivingScore.toStringAsFixed(0)}%',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const Gap(12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Telemetry',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(12),
                  _DataRow(
                    label: 'Battery',
                    value: _percent(telemetry.batteryPercent),
                  ),
                  _DataRow(
                    label: 'SOH',
                    value: _percent(telemetry.estimatedSohPercent),
                  ),
                  _DataRow(
                    label: 'Speed',
                    value: _number(telemetry.speedKph, 'km/h'),
                  ),
                  _DataRow(
                    label: 'Battery Voltage',
                    value: _number(
                      telemetry.batteryPackVoltage ??
                          telemetry.controlModuleVoltage,
                      'V',
                    ),
                  ),
                  _DataRow(
                    label: 'Battery Power',
                    value: _number(telemetry.batteryPowerKw, 'kW'),
                  ),
                  _DataRow(
                    label: 'Temperature',
                    value: _number(
                      telemetry.batteryTempC ?? telemetry.coolantTempC,
                      '°C',
                    ),
                  ),
                  _DataRow(
                    label: 'Battery Current',
                    value: _number(telemetry.batteryCurrent, 'A'),
                  ),
                  _DataRow(
                    label: 'Cell Delta',
                    value: _number(telemetry.cellDeltaMv, 'mV'),
                  ),
                ],
              ),
            ),
          ),
          const Gap(12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver Analytics',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(12),
                  _DataRow(
                    label: 'Smooth Driving',
                    value: '${analytics.smoothDrivingScore.toStringAsFixed(0)}%',
                  ),
                  _DataRow(
                    label: 'Efficiency',
                    value: '${analytics.efficiencyScore.toStringAsFixed(0)}%',
                  ),
                  _DataRow(
                    label: 'Average Speed',
                    value: '${analytics.averageSpeedKph.toStringAsFixed(1)} km/h',
                  ),
                  _DataRow(
                    label: 'Peak Speed',
                    value: '${analytics.peakSpeedKph.toStringAsFixed(1)} km/h',
                  ),
                  _DataRow(
                    label: 'Trip Distance',
                    value: '${analytics.tripDistanceKm.toStringAsFixed(1)} km',
                  ),
                  _DataRow(
                    label: 'Harsh Events',
                    value:
                        '${analytics.harshAccelerationEvents + analytics.harshBrakingEvents}',
                  ),
                ],
              ),
            ),
          ),
          const Gap(12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                telemetry.sourceSummary,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(ObdConnectionStage stage) {
    return switch (stage) {
      ObdConnectionStage.connected => 'Connected',
      ObdConnectionStage.connecting => 'Connecting',
      ObdConnectionStage.scanning => 'Scanning',
      ObdConnectionStage.bluetoothOff => 'Bluetooth Off',
      ObdConnectionStage.unsupported => 'Unsupported',
      ObdConnectionStage.error => 'Needs Attention',
      _ => 'Ready',
    };
  }

  static String _percent(double? value) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(0)}%';

  static String _number(double? value, String unit) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(1)} $unit';
}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;

  const _DataRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AggregateCard extends StatelessWidget {
  final String title;
  final ObdHistoryAggregate aggregate;

  const _AggregateCard({
    required this.title,
    required this.aggregate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(12),
            _DataRow(
              label: 'Sessions',
              value: '${aggregate.sessionCount}',
            ),
            _DataRow(
              label: 'Distance',
              value: '${aggregate.totalDistanceKm.toStringAsFixed(1)} km',
            ),
            _DataRow(
              label: 'Efficiency',
              value: '${aggregate.averageEfficiencyScore.toStringAsFixed(0)}%',
            ),
            _DataRow(
              label: 'Smooth Driving',
              value:
                  '${aggregate.averageSmoothDrivingScore.toStringAsFixed(0)}%',
            ),
            _DataRow(
              label: 'Battery',
              value: '${aggregate.averageBatteryPercent.toStringAsFixed(0)}%',
            ),
            _DataRow(
              label: 'SOH',
              value: '${aggregate.averageSohPercent.toStringAsFixed(0)}%',
            ),
            _DataRow(
              label: 'Harsh Events',
              value: '${aggregate.harshEvents}',
            ),
          ],
        ),
      ),
    );
  }
}
