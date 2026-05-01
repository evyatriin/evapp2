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
    final statusColor = _statusColor(stage, theme);

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // ── Status bar ─────────────────────────────────────────────
              _StatusBar(
                stage: stage,
                statusMessage: session.statusMessage,
                statusColor: statusColor,
                device: session.selectedDevice,
              ),
              const Gap(12),

              // ── Action buttons ──────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          isScanning ? controller.stopScan : controller.startScan,
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

              // ── Device list when not connected ──────────────────────────
              if (!isConnected) ...[
                _DeviceList(
                  devices: session.scanDevices,
                  isScanning: isScanning,
                  statusMessage: session.statusMessage,
                  onConnect: controller.connect,
                ),
                const Gap(12),
              ],

              // ── Connected view ──────────────────────────────────────────
              if (isConnected) ...[
                FilledButton.icon(
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                ),
                const Gap(16),

                // SOC prediction banner (shown above metrics when driving)
                _SocPredictionCard(
                  prediction: session.socPrediction,
                  thresholdPct: session.chargeThresholdPct,
                  onThresholdChanged: controller.setChargeThresholdLive,
                  onThresholdCommit: controller.commitChargeThreshold,
                ),
                const Gap(12),

                // Live metrics grid
                _MetricGrid(telemetry: session.telemetry),
                const Gap(12),

                // Driver analytics
                _AnalyticsCard(analytics: session.analytics),
                const Gap(12),

                // Source / profile info
                if (session.telemetry.sourceSummary.isNotEmpty)
                  _InfoCard(
                    title: session.telemetry.evProfileName ?? 'OBD Profile',
                    description: session.telemetry.sourceSummary,
                    accent: const Color(0xFF0F5132),
                  ),
                const Gap(12),
              ],

              // ── Diagnostics ─────────────────────────────────────────────
              _DiagnosticsCard(
                diagnostics: session.diagnostics,
                onClear: controller.clearDiagnostics,
              ),
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

// ─── Status bar ──────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final ObdConnectionStage stage;
  final String statusMessage;
  final Color statusColor;
  final ObdScanDevice? device;

  const _StatusBar({
    required this.stage,
    required this.statusMessage,
    required this.statusColor,
    required this.device,
  });

  static String _stageLabel(ObdConnectionStage stage) {
    return switch (stage) {
      ObdConnectionStage.connected => 'Connected',
      ObdConnectionStage.connecting => 'Connecting…',
      ObdConnectionStage.scanning => 'Scanning…',
      ObdConnectionStage.bluetoothOff => 'Bluetooth Off',
      ObdConnectionStage.unsupported => 'Not Supported',
      ObdConnectionStage.error => 'Error',
      _ => 'Ready',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device?.name ?? _stageLabel(stage),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                const Gap(2),
                Text(
                  statusMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SOC Prediction card ──────────────────────────────────────────────────────

class _SocPredictionCard extends StatelessWidget {
  final SocPrediction? prediction;
  final double thresholdPct;
  final void Function(double) onThresholdChanged;
  final Future<void> Function(double) onThresholdCommit;

  const _SocPredictionCard({
    required this.prediction,
    required this.thresholdPct,
    required this.onThresholdChanged,
    required this.onThresholdCommit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pred = prediction;
    final isUrgent = pred?.isUrgent ?? false;

    final bgColor = isUrgent
        ? const Color(0xFFFFF3E0)
        : const Color(0xFFE8F5E9);
    final accentColor = isUrgent
        ? const Color(0xFFE65100)
        : const Color(0xFF2E7D32);
    final iconData = isUrgent ? Icons.warning_amber_rounded : Icons.bolt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(iconData, color: accentColor, size: 22),
              const Gap(8),
              Text(
                'Charge Prediction',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const Gap(8),

          // Prediction summary
          Text(
            pred?.summary ?? 'Connect OBD to start prediction.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1A2332),
              height: 1.35,
            ),
          ),

          // Detailed numbers when available
          if (pred != null && pred.hasData && pred.remainingKm != null) ...[
            const Gap(8),
            Row(
              children: [
                _PredStat(
                  label: 'Distance',
                  value: '${pred.remainingKm!.toStringAsFixed(0)} km',
                  icon: Icons.route,
                ),
                const Gap(16),
                if (pred.remainingMinutes != null)
                  _PredStat(
                    label: 'Time',
                    value: '${pred.remainingMinutes!.toStringAsFixed(0)} min',
                    icon: Icons.timer_outlined,
                  ),
                const Gap(16),
                if (pred.depletionRatePerKm != null)
                  _PredStat(
                    label: 'Rate',
                    value:
                        '${pred.depletionRatePerKm!.toStringAsFixed(2)} %/km',
                    icon: Icons.trending_down,
                  ),
              ],
            ),
          ],

          const Gap(14),
          const Divider(height: 1, color: Color(0xFFCFD8DC)),
          const Gap(10),

          // Threshold slider
          Row(
            children: [
              Icon(Icons.battery_charging_full,
                  size: 16, color: const Color(0xFF455A64)),
              const Gap(6),
              Text(
                'Charge at: ${thresholdPct.toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF37474F),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: thresholdPct.clamp(5.0, 80.0),
              min: 5,
              max: 80,
              divisions: 15,
              activeColor: accentColor,
              label: '${thresholdPct.toStringAsFixed(0)}%',
              onChanged: (v) => onThresholdChanged(v),
              onChangeEnd: (v) => onThresholdCommit(v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('5%', style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF90A4AE))),
              Text('80%', style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFF90A4AE))),
            ],
          ),
        ],
      ),
    );
  }
}

class _PredStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _PredStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF607D8B)),
        const Gap(4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A2332),
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF607D8B),
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Diagnostics card ────────────────────────────────────────────────────────

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
              'Recent transport and adapter events.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF475569),
                height: 1.35,
              ),
            ),
            const Gap(12),
            if (entries.isEmpty)
              Text(
                'No diagnostics captured yet.',
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

// ─── Info card ───────────────────────────────────────────────────────────────

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

// ─── Device list ─────────────────────────────────────────────────────────────

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
        title: isScanning ? 'Looking for adapters…' : 'No adapters yet',
        description:
            isScanning
                ? 'Keep the adapter powered on and nearby. Results appear here automatically.'
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

// ─── Metric grid ─────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final ObdTelemetrySnapshot telemetry;

  const _MetricGrid({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    // Prefer GPS speed; fall back to OBD speed
    final speedDisplay = _number(telemetry.effectiveSpeedKph, 'km/h');
    final speedLabel = telemetry.gpsSpeedKph != null ? 'Speed (GPS)' : 'Speed';

    final tiles = [
      _MetricTileData('Battery SOC', _percent(telemetry.batteryPercent),
          Icons.battery_full, _socColor(telemetry.batteryPercent)),
      _MetricTileData('SOH', _percent(telemetry.estimatedSohPercent),
          Icons.health_and_safety, const Color(0xFF1565C0)),
      _MetricTileData(speedLabel, speedDisplay, Icons.speed,
          const Color(0xFF0F5132)),
      _MetricTileData(
        'Voltage',
        _number(telemetry.batteryPackVoltage ?? telemetry.controlModuleVoltage,
            'V'),
        Icons.bolt,
        const Color(0xFF6A1B9A),
      ),
      _MetricTileData('Power', _number(telemetry.batteryPowerKw, 'kW'),
          Icons.ev_station, const Color(0xFF00695C)),
      _MetricTileData(
        'Temp',
        _number(telemetry.batteryTempC ?? telemetry.coolantTempC, '°C'),
        Icons.thermostat,
        const Color(0xFFBF360C),
      ),
      _MetricTileData(
        'Elevation',
        telemetry.elevationM != null
            ? _number(telemetry.elevationM, 'm')
            : 'Awaiting GPS…',
        Icons.landscape,
        const Color(0xFF37474F),
      ),
      if (telemetry.gradePct != null)
        _MetricTileData(
          'Road Grade',
          '${telemetry.gradePct!.toStringAsFixed(1)}%',
          Icons.terrain,
          telemetry.gradePct!.abs() > 5
              ? const Color(0xFFE65100)
              : const Color(0xFF37474F),
        ),
      if (telemetry.cellDeltaMv != null)
        _MetricTileData(
          'Cell Δ',
          _number(telemetry.cellDeltaMv, 'mV'),
          Icons.cell_tower,
          telemetry.cellDeltaMv! > 50
              ? const Color(0xFFBF360C)
              : const Color(0xFF0F5132),
        ),
      if (telemetry.batteryCurrent != null)
        _MetricTileData(
          'Current',
          _number(telemetry.batteryCurrent, 'A'),
          Icons.electrical_services,
          const Color(0xFF1565C0),
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
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(tile.icon, color: tile.color, size: 22),
              const Spacer(),
              Text(tile.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF607D8B))),
              const Gap(3),
              Text(
                tile.value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
              ),
            ],
          ),
        );
      },
    );
  }

  static Color _socColor(double? soc) {
    if (soc == null) return const Color(0xFF607D8B);
    if (soc <= 20) return const Color(0xFFBF360C);
    if (soc <= 40) return const Color(0xFFE65100);
    return const Color(0xFF2E7D32);
  }

  static String _percent(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(0)}%';

  static String _number(double? value, String unit) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} $unit';
}

class _MetricTileData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricTileData(this.label, this.value, this.icon, this.color);
}

// ─── Analytics card ───────────────────────────────────────────────────────────

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
            'Trip Analytics',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
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
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─── Error fallback ───────────────────────────────────────────────────────────

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
                      'OBD Scanner',
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
