import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/feature_flags.dart';
import '../../domain/charging_session_models.dart';
import '../providers/charging_session_provider.dart';
import 'charging_session_screen.dart';

class ChargerConfirmScreen extends ConsumerStatefulWidget {
  const ChargerConfirmScreen({
    super.key,
    required this.chargerDetails,
  });

  final ChargerDetails chargerDetails;

  @override
  ConsumerState<ChargerConfirmScreen> createState() =>
      _ChargerConfirmScreenState();
}

class _ChargerConfirmScreenState extends ConsumerState<ChargerConfirmScreen> {
  bool _isStarting = false;

  Future<void> _startCharging() async {
    setState(() => _isStarting = true);

    try {
      await ref.read(chargingSessionProvider.notifier).startSession(
            chargerId: widget.chargerDetails.chargerId,
            connectorId: widget.chargerDetails.connectorId,
            rate: widget.chargerDetails.chargingRateInrPerKwh,
          );

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => const ChargingSessionScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to start session: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.becknChargingEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final charger = widget.chargerDetails;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Charger Details'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Charger name card
                    Card(
                      elevation: 0,
                      color: colorScheme.primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.ev_station,
                                  color: colorScheme.onPrimaryContainer,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        charger.chargerName,
                                        style: textTheme.titleLarge?.copyWith(
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.place_outlined,
                                            size: 14,
                                            color: colorScheme
                                                .onPrimaryContainer
                                                .withOpacity(0.8),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              charger.locationName,
                                              style:
                                                  textTheme.bodyMedium?.copyWith(
                                                color: colorScheme
                                                    .onPrimaryContainer
                                                    .withOpacity(0.8),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Details grid
                    Text(
                      'Charging Details',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _DetailRow(
                      icon: Icons.bolt,
                      label: 'Power Output',
                      value: '${charger.powerKw.toStringAsFixed(1)} kW',
                    ),
                    _DetailRow(
                      icon: Icons.electrical_services_outlined,
                      label: 'Connector Type',
                      value: charger.connectorType.toUpperCase(),
                    ),
                    _DetailRow(
                      icon: Icons.currency_rupee,
                      label: 'Charging Rate',
                      value:
                          '₹${charger.chargingRateInrPerKwh.toStringAsFixed(2)} / kWh',
                    ),
                    _DetailRow(
                      icon: Icons.check_circle_outline,
                      label: 'Availability',
                      value: charger.canStartImmediately
                          ? 'Available now'
                          : 'Check at charger',
                      valueColor: charger.canStartImmediately
                          ? Colors.green
                          : colorScheme.onSurface,
                    ),

                    const SizedBox(height: 24),

                    // Info notice
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Charging will begin immediately. '
                              'You will be charged based on actual energy consumed.',
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _isStarting ? null : _startCharging,
                    icon: _isStarting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(
                      _isStarting ? 'Starting...' : 'Start Charging',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _isStarting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel'),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
