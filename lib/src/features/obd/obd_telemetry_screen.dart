// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';

import 'obd_controller.dart';
import 'obd_models.dart';

class ObdTelemetryScreen extends ConsumerWidget {
  const ObdTelemetryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ObdSessionState session;
    try {
      session = ref.watch(obdSessionControllerProvider);
    } catch (e) {
      return _ErrorFallback(error: e);
    }

    final ObdSessionController controller;
    try {
      controller = ref.read(obdSessionControllerProvider.notifier);
    } catch (e) {
      return _ErrorFallback(error: e);
    }

    final theme = Theme.of(context);
    final isConnected = session.selectedDevice != null;
    final isScanning = session.isScanning;
    final stage = session.stage;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: context.canPop(),
        leading:
            context.canPop()
                ? null
                : IconButton(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home_outlined),
                  tooltip: 'Go to home',
                ),
        title: const Text('OBD Scanner'),
        actions: [
          IconButton(
            onPressed: () => context.push('/obd/analytics'),
            icon: const Icon(Icons.insights),
            tooltip: 'View analytics',
          ),
        ],
      ),
      body: ColoredBox(
        color: const Color(0xFFF5F7F3),
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                session.selectedDevice?.name ??
                    'Scan for your OBD-II adapter and connect.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF334155),
                ),
              ),
              const Gap(16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${_statusLabel(stage)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Gap(8),
                      Text(session.statusMessage),
                      if (stage == ObdConnectionStage.bluetoothOff) ...[
                        const Gap(8),
                        const Text('Turn on Bluetooth, then tap Prepare or Scan.'),
                      ],
                    ],
                  ),
                ),
              ),
              const Gap(12),
              _DiagnosticsCard(
                diagnostics: session.diagnostics,
                onClear: controller.clearDiagnostics,
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isScanning
                          ? controller.stopScan
                          : controller.startScan,
                      icon: Icon(
                        isScanning
                            ? Icons.stop_circle
                            : Icons.bluetooth_searching,
                      ),
                      label: Text(isScanning ? 'Stop Scan' : 'Scan'),
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: controller.ensureSetup,
                      icon: const Icon(Icons.settings_bluetooth),
                      label: const Text('Prepare'),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              if (!isConnected) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Devices found: ${session.scanDevices.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Gap(12),
                if (session.scanDevices.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        isScanning
                            ? 'Scanning nearby devices... keep the adapter powered on.'
                            : 'No adapters found yet.',
                      ),
                    ),
                  )
                else
                  for (final device in session.scanDevices)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  device.transport == ObdTransport.ble
                                      ? Icons.bluetooth
                                      : Icons.settings_input_component,
                                ),
                                const Gap(12),
                                Expanded(
                                  child: Text(
                                    device.name,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Gap(8),
                            Text(
                              '${device.transportLabel}${device.rssi != 0 ? ' • RSSI ${device.rssi}' : ''}',
                            ),
                            const Gap(4),
                            Text(device.macAddress ?? device.id),
                            const Gap(12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: device.isConnectable
                                    ? () => controller.connect(device)
                                    : null,
                                child: const Text('Connect'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ] else ...[
                FilledButton.icon(
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
                const Gap(12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live OBD Data',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Gap(12),
                        Text('Battery: ${_MetricGrid._percent(session.telemetry.batteryPercent)}'),
                        Text('SOH: ${_MetricGrid._percent(session.telemetry.estimatedSohPercent)}'),
                        Text('Speed: ${_MetricGrid._number(session.telemetry.speedKph, 'km/h')}'),
                        Text(
                          'Voltage: ${_MetricGrid._number(session.telemetry.batteryPackVoltage ?? session.telemetry.controlModuleVoltage, 'V')}',
                        ),
                        Text('Power: ${_MetricGrid._number(session.telemetry.batteryPowerKw, 'kW')}'),
                        Text(
                          'Temperature: ${_MetricGrid._number(session.telemetry.batteryTempC ?? session.telemetry.coolantTempC, '°C')}',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
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

  static Color _statusColor(ObdConnectionStage stage, ThemeData theme) {
    return switch (stage) {
      ObdConnectionStage.connected => const Color(0xFF2E7D32),
      ObdConnectionStage.connecting => theme.colorScheme.primary,
      ObdConnectionStage.scanning => const Color(0xFF1565C0),
      ObdConnectionStage.bluetoothOff => const Color(0xFFEF6C00),
      ObdConnectionStage.unsupported => theme.colorScheme.error,
      ObdConnectionStage.error => theme.colorScheme.error,
      _ => const Color(0xFF455A64),
    };
  }
}

class _DiagnosticsCard extends StatelessWidget {
  final List<ObdDiagnosticEntry> diagnostics;
  final VoidCallback onClear;

  const _DiagnosticsCard({
    required this.diagnostics,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = diagnostics.reversed.take(12).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Connection Diagnostics',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: diagnostics.isEmpty ? null : onClear,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const Gap(8),
            Text(
              'Recent transport and adapter events. This helps pinpoint whether failure happens during scan, connect, BLE service discovery, ELM setup, or polling.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF475569),
                height: 1.35,
              ),
            ),
            const Gap(12),
            if (entries.isEmpty)
              Text(
                'No diagnostics captured yet. Start a scan or connection attempt to populate this timeline.',
                style: theme.textTheme.bodyMedium,
              )
            else
              for (final entry in entries)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2F2EB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          entry.phase.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF0F5132),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.35,
                              ),
                            ),
                            const Gap(4),
                            Text(
                              DateFormat('HH:mm:ss').format(entry.timestamp),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
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

class _HeroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _HeroCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F5132), Color(0xFF1E7A53)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Gap(8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String description;
  final Color accent;

  const _InfoCard({
    required this.title,
    required this.description,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const Gap(8),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<ObdScanDevice> devices;
  final bool isScanning;
  final String statusMessage;
  final Future<void> Function(ObdScanDevice device) onConnect;

  const _DeviceList({
    required this.devices,
    required this.isScanning,
    required this.statusMessage,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (devices.isEmpty) {
      return _InfoCard(
        title: isScanning ? 'Looking for adapters...' : 'No adapters yet',
        description:
            isScanning
                ? 'Keep the adapter powered on and nearby. Results will appear here.'
                : statusMessage,
        accent: theme.colorScheme.primary,
      );
    }

    return Column(
      children: [
        for (final device in devices)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE6F3EC),
                child: Icon(
                  device.transport == ObdTransport.ble
                      ? Icons.bluetooth
                      : Icons.settings_input_component,
                  color: const Color(0xFF0F5132),
                ),
              ),
              title: Text(
                device.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${device.transportLabel}${device.rssi != 0 ? ' • RSSI ${device.rssi}' : ''}',
              ),
              trailing: FilledButton(
                onPressed:
                    device.isConnectable ? () => onConnect(device) : null,
                child: const Text('Connect'),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final ObdTelemetrySnapshot telemetry;

  const _MetricGrid({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _MetricTileData(
        'Battery',
        _percent(telemetry.batteryPercent),
        Icons.battery_full,
      ),
      _MetricTileData(
        'SOH',
        _percent(telemetry.estimatedSohPercent),
        Icons.health_and_safety,
      ),
      _MetricTileData(
        'Speed',
        _number(telemetry.speedKph, 'km/h'),
        Icons.speed,
      ),
      _MetricTileData(
        'Voltage',
        _number(
          telemetry.batteryPackVoltage ?? telemetry.controlModuleVoltage,
          'V',
        ),
        Icons.bolt,
      ),
      _MetricTileData(
        'Power',
        _number(telemetry.batteryPowerKw, 'kW'),
        Icons.ev_station,
      ),
      _MetricTileData(
        'Temp',
        _number(telemetry.batteryTempC ?? telemetry.coolantTempC, '°C'),
        Icons.thermostat,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.25,
      ),
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tile.icon, color: const Color(0xFF0F5132)),
              const Spacer(),
              Text(tile.label, style: Theme.of(context).textTheme.bodySmall),
              const Gap(4),
              Text(
                tile.value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _percent(double? value) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(0)}%';

  static String _number(double? value, String unit) =>
      value == null ? 'Unavailable' : '${value.toStringAsFixed(1)} $unit';
}

class _MetricTileData {
  final String label;
  final String value;
  final IconData icon;

  const _MetricTileData(this.label, this.value, this.icon);
}

class _AnalyticsCard extends StatelessWidget {
  final DriverAnalytics analytics;

  const _AnalyticsCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Driver analytics',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(12),
          _AnalyticsRow(
            label: 'Smooth driving',
            value: '${analytics.smoothDrivingScore.toStringAsFixed(0)}%',
          ),
          _AnalyticsRow(
            label: 'Efficiency',
            value: '${analytics.efficiencyScore.toStringAsFixed(0)}%',
          ),
          _AnalyticsRow(
            label: 'Average speed',
            value: '${analytics.averageSpeedKph.toStringAsFixed(1)} km/h',
          ),
          _AnalyticsRow(
            label: 'Peak speed',
            value: '${analytics.peakSpeedKph.toStringAsFixed(1)} km/h',
          ),
          _AnalyticsRow(
            label: 'Harsh events',
            value:
                '${analytics.harshAccelerationEvents + analytics.harshBrakingEvents}',
          ),
          _AnalyticsRow(
            label: 'Trip distance',
            value: '${analytics.tripDistanceKm.toStringAsFixed(1)} km',
          ),
        ],
      ),
    );
  }
}

class _AnalyticsRow extends StatelessWidget {
  final String label;
  final String value;

  const _AnalyticsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

class _ErrorFallback extends StatelessWidget {
  final Object error;

  const _ErrorFallback({required this.error});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F7F3),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Battery & OBD Analytics',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Gap(24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OBD module failed to initialise',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade700,
                        fontSize: 16,
                      ),
                    ),
                    const Gap(8),
                    SelectableText(
                      error.toString(),
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
