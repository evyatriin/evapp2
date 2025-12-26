import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../vehicle_profile/vehicle_provider.dart';

class CostCalculatorSheet extends ConsumerStatefulWidget {
  final String stationCost; // e.g., "₹15-25 / kWh" or "₹18 / kWh"
  final String stationName;

  const CostCalculatorSheet({
    super.key,
    required this.stationCost,
    required this.stationName,
  });

  @override
  ConsumerState<CostCalculatorSheet> createState() => _CostCalculatorSheetState();
}

class _CostCalculatorSheetState extends ConsumerState<CostCalculatorSheet> {
  double _currentSoC = 20;
  double _targetSoC = 80;

  double get _batteryCapacity {
    // Get from vehicle if available, else use default
    final vehicles = ref.read(vehicleProvider);
    final vehicle = vehicles.isNotEmpty ? vehicles.first : null;
    // Using a reasonable default for Indian EVs
    return vehicle?.estimatedRange != null 
        ? (vehicle!.estimatedRange / 5.0).clamp(20.0, 100.0) // Rough estimate
        : 40.0; // Default: 40 kWh (like Nexon EV Max)
  }

  double get _tariffRate {
    // Parse tariff from station cost string
    final costStr = widget.stationCost;
    final regex = RegExp(r'₹(\d+)');
    final match = regex.firstMatch(costStr);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 18.0;
    }
    return 18.0; // Default ₹18/kWh
  }

  double get _kWhRequired {
    final socDiff = (_targetSoC - _currentSoC) / 100;
    return _batteryCapacity * socDiff;
  }

  double get _estimatedCost {
    return _kWhRequired * _tariffRate;
  }

  String _formatDuration(double kWh) {
    // Assume 50 kW DC charging
    final hours = kWh / 50;
    final minutes = (hours * 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    return '${(minutes / 60).floor()}h ${minutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(PhosphorIcons.calculator(PhosphorIconsStyle.duotone), 
                   color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Charging Cost Calculator',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.stationName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.secondary,
            ),
          ),
          const SizedBox(height: 12),

          // Current SoC Slider
          Text('Current Battery Level', style: theme.textTheme.titleSmall),
          Row(
            children: [
              Icon(PhosphorIcons.batteryLow(PhosphorIconsStyle.duotone), 
                   color: Colors.red),
              Expanded(
                child: Slider(
                  value: _currentSoC,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_currentSoC.round()}%',
                  onChanged: (value) {
                    if (value < _targetSoC) {
                      setState(() => _currentSoC = value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 50,
                child: Text('${_currentSoC.round()}%', 
                       style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Target SoC Slider
          Text('Charge To', style: theme.textTheme.titleSmall),
          Row(
            children: [
              Icon(PhosphorIcons.batteryFull(PhosphorIconsStyle.duotone), 
                   color: Colors.green),
              Expanded(
                child: Slider(
                  value: _targetSoC,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${_targetSoC.round()}%',
                  onChanged: (value) {
                    if (value > _currentSoC) {
                      setState(() => _targetSoC = value);
                    }
                  },
                ),
              ),
              SizedBox(
                width: 50,
                child: Text('${_targetSoC.round()}%', 
                       style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Results
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ResultCard(
                icon: PhosphorIcons.lightning(PhosphorIconsStyle.duotone),
                label: 'Energy',
                value: '${_kWhRequired.toStringAsFixed(1)} kWh',
                color: Colors.orange,
              ),
              _ResultCard(
                icon: PhosphorIcons.clock(PhosphorIconsStyle.duotone),
                label: 'Time (50kW)',
                value: _formatDuration(_kWhRequired),
                color: Colors.blue,
              ),
              _ResultCard(
                icon: PhosphorIcons.currencyInr(PhosphorIconsStyle.duotone),
                label: 'Cost',
                value: '₹${_estimatedCost.toStringAsFixed(0)}',
                color: Colors.green,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.info(PhosphorIconsStyle.duotone), 
                     size: 20, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tariff: ${widget.stationCost} • Battery: ${_batteryCapacity.toStringAsFixed(0)} kWh',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ResultCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
