import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class CheckInSheet extends StatefulWidget {
  const CheckInSheet({super.key});

  @override
  State<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<CheckInSheet> {
  int _step = 0;

  double _speed = 30.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Verify Station', style: theme.textTheme.headlineSmall),
          const Gap(24),
          if (_step == 0) ...[
            Text('Is this charger working?', style: theme.textTheme.titleMedium),
            const Gap(16),
            Row(
              children: [
                Expanded(child: _buildStatusBtn('Working', Colors.green, PhosphorIcons.checkCircle())),
                const Gap(12),
                Expanded(child: _buildStatusBtn('Busy', Colors.orange, PhosphorIcons.clock())),
                const Gap(12),
                Expanded(child: _buildStatusBtn('Broken', Colors.red, PhosphorIcons.xCircle())),
              ],
            ),
          ] else if (_step == 1) ...[
            Text('Charging Speed (kW)', style: theme.textTheme.titleMedium),
            const Gap(8),
            Text('${_speed.toInt()} kW', style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary)),
            Slider(
              value: _speed,
              min: 0,
              max: 150,
              divisions: 15,
              label: '${_speed.toInt()} kW',
              onChanged: (val) => setState(() => _speed = val),
            ),
            const Gap(24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Submit Report'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBtn(String label, Color color, IconData icon) {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          if (label == 'Working') {
            _step = 1;
          } else {
            _submit();
          }
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32),
          const Gap(8),
          Text(label),
        ],
      ),
    );
  }

  void _submit() {
    Navigator.pop(context);
    // Show confetti dialog or snackbar
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Awesome!'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, size: 48, color: Colors.amber),
            Gap(16),
            Text('You earned +10 Volts!'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}
