import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/feature_flags.dart';
import '../../domain/charging_session_models.dart';
import '../providers/charging_session_provider.dart';

class ChargingSessionScreen extends ConsumerStatefulWidget {
  const ChargingSessionScreen({super.key});

  @override
  ConsumerState<ChargingSessionScreen> createState() =>
      _ChargingSessionScreenState();
}

class _ChargingSessionScreenState extends ConsumerState<ChargingSessionScreen> {
  Timer? _durationTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _startTime;

  bool _isStopping = false;
  bool _isConfirmingPayment = false;

  @override
  void initState() {
    super.initState();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _stopCharging() async {
    setState(() => _isStopping = true);

    try {
      final paymentData =
          await ref.read(chargingSessionProvider.notifier).endSession();

      if (!mounted) return;

      final session = ref.read(chargingSessionProvider);
      _showPaymentBottomSheet(
        paymentUri:
            session?.paymentUri ?? paymentData['payment_uri'] as String?,
        finalCostInr:
            session?.finalCostInr ??
            (paymentData['final_cost_inr'] as num?)?.toDouble(),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to stop session: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isStopping = false);
    }
  }

  void _showPaymentBottomSheet({String? paymentUri, double? finalCostInr}) {
    final parentNavigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final sheetNavigator = Navigator.of(sheetContext);
        return _PaymentBottomSheet(
          paymentUri: paymentUri,
          finalCostInr: finalCostInr,
          onPaymentConfirmed: (referenceId) async {
            setState(() => _isConfirmingPayment = true);
            try {
              await ref
                  .read(chargingSessionProvider.notifier)
                  .confirmPayment(referenceId);

              if (!mounted) return;
              sheetNavigator.pop();
              // Return to home
              parentNavigator.popUntil((route) => route.isFirst);
            } catch (e) {
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    'Payment confirmation failed: ${e.toString().replaceFirst('Exception: ', '')}',
                  ),
                  backgroundColor: errorColor,
                ),
              );
            } finally {
              if (mounted) setState(() => _isConfirmingPayment = false);
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!FeatureFlags.becknChargingEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final session = ref.watch(chargingSessionProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Sync start time
    if (session != null && _startTime == null) {
      _startTime = session.startTime;
    }

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (session.status == SessionStatus.failed) {
      return _buildErrorScreen(context, session, colorScheme, textTheme);
    }

    final reading = session.latestReading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Charging Session'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status banner
            _StatusBanner(status: session.status),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Duration timer
                    Text(
                      _formatDuration(_elapsed),
                      style: textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2,
                        color: colorScheme.primary,
                      ),
                    ),
                    Text(
                      'Duration',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Energy and cost — large display
                    Row(
                      children: [
                        Expanded(
                          child: _BigMetricCard(
                            label: 'Energy',
                            value:
                                reading != null
                                    ? reading.energyKwh.toStringAsFixed(2)
                                    : '0.00',
                            unit: 'kWh',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BigMetricCard(
                            label: 'Cost',
                            value:
                                reading != null
                                    ? '₹${reading.costInr.toStringAsFixed(2)}'
                                    : '₹0.00',
                            unit: '',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Metrics grid
                    _MetricsGrid(reading: reading),

                    const SizedBox(height: 16),

                    // Rate info
                    if (reading != null && reading.chargingRateInrPerKwh > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.currency_rupee,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            Text(
                              '${reading.chargingRateInrPerKwh.toStringAsFixed(2)} / kWh',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Stop charging button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton.tonalIcon(
                onPressed:
                    _isStopping ||
                            _isConfirmingPayment ||
                            session.status != SessionStatus.charging
                        ? null
                        : _stopCharging,
                icon:
                    _isStopping
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        )
                        : const Icon(Icons.stop_circle_outlined),
                label: Text(_isStopping ? 'Stopping...' : 'Stop Charging'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                  textStyle: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(
    BuildContext context,
    ChargingSession session,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session Error')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Charging Failed',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                session.errorMessage ??
                    'An unexpected error occurred. Please try again.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () {
                  ref.read(chargingSessionProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (status) {
      SessionStatus.starting => (
        'Starting...',
        Icons.hourglass_empty,
        colorScheme.tertiary,
      ),
      SessionStatus.charging => ('Charging Active', Icons.bolt, Colors.green),
      SessionStatus.stopping => (
        'Stopping...',
        Icons.hourglass_bottom,
        colorScheme.tertiary,
      ),
      SessionStatus.awaitingPayment => (
        'Awaiting Payment',
        Icons.payment,
        colorScheme.primary,
      ),
      SessionStatus.paymentConfirmed || SessionStatus.completed => (
        'Completed',
        Icons.check_circle,
        Colors.green,
      ),
      SessionStatus.failed => ('Failed', Icons.error, colorScheme.error),
      SessionStatus.idle => ('Ready', Icons.power, colorScheme.outline),
    };

    return Container(
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigMetricCard extends StatelessWidget {
  const _BigMetricCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.reading});

  final MeterReading? reading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final metrics = [
      (
        'Current',
        '${reading?.currentAmps.toStringAsFixed(1) ?? '--'} A',
        Icons.electric_bolt_outlined,
      ),
      (
        'Voltage',
        '${reading?.voltageVolts.toStringAsFixed(0) ?? '--'} V',
        Icons.power_input,
      ),
      (
        'Power',
        '${reading?.powerKw.toStringAsFixed(2) ?? '--'} kW',
        Icons.flash_on_outlined,
      ),
      (
        'SOC',
        '${reading?.socPercent.toStringAsFixed(0) ?? '--'} %',
        Icons.battery_charging_full,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children:
          metrics.map((m) {
            final (label, value, icon) = m;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          value,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }
}

class _PaymentBottomSheet extends StatefulWidget {
  const _PaymentBottomSheet({
    required this.onPaymentConfirmed,
    this.paymentUri,
    this.finalCostInr,
  });

  final String? paymentUri;
  final double? finalCostInr;
  final Future<void> Function(String referenceId) onPaymentConfirmed;

  @override
  State<_PaymentBottomSheet> createState() => _PaymentBottomSheetState();
}

class _PaymentBottomSheetState extends State<_PaymentBottomSheet> {
  bool _isLaunchingUpi = false;
  bool _isConfirming = false;
  bool _upiLaunched = false;

  Future<void> _launchUpi() async {
    if (widget.paymentUri == null) return;

    setState(() => _isLaunchingUpi = true);
    try {
      final uri = Uri.parse(widget.paymentUri!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        setState(() => _upiLaunched = true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No UPI app found. Please install a UPI payment app and try again.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not launch payment: $e')));
    } finally {
      if (mounted) setState(() => _isLaunchingUpi = false);
    }
  }

  Future<void> _confirmPayment() async {
    setState(() => _isConfirming = true);
    // Use a timestamp-based reference ID since we don't have a separate input
    final referenceId = 'REF${DateTime.now().millisecondsSinceEpoch}';
    try {
      await widget.onPaymentConfirmed(referenceId);
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Charging Complete',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Total amount
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    'Total Amount',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.finalCostInr != null
                        ? '₹${widget.finalCostInr!.toStringAsFixed(2)}'
                        : 'Calculating...',
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (widget.paymentUri != null) ...[
              FilledButton.icon(
                onPressed: _isLaunchingUpi ? null : _launchUpi,
                icon:
                    _isLaunchingUpi
                        ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                        : const Icon(Icons.payment),
                label: const Text('Pay Now (UPI)'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            OutlinedButton.icon(
              onPressed: _isConfirming ? null : _confirmPayment,
              icon:
                  _isConfirming
                      ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.check_circle_outline),
              label: Text(_isConfirming ? 'Confirming...' : 'Payment Done'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            if (_upiLaunched) ...[
              const SizedBox(height: 8),
              Text(
                'UPI app launched. Return here after completing payment and tap "Payment Done".',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
