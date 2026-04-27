import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../charge/charging_service.dart';
import '../authentication/user_provider.dart';

class SavedChargersList extends ConsumerStatefulWidget {
  const SavedChargersList({super.key});

  @override
  ConsumerState<SavedChargersList> createState() => _SavedChargersListState();
}

class _SavedChargersListState extends ConsumerState<SavedChargersList> {
  final _chargingService = ChargingService();
  List<Map<String, dynamic>> _savedChargers = [];
  bool _isLoading = true;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadSavedChargers();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
      });
      _sortByDistance();
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _loadSavedChargers() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(userProvider);
      if (user != null) {
        final chargers = await _chargingService.getSavedChargers(user.id);
        setState(() {
          _savedChargers = List<Map<String, dynamic>>.from(chargers);
        });
        _sortByDistance();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading saved chargers: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sortByDistance() {
    if (_currentPosition == null || _savedChargers.isEmpty) return;

    _savedChargers.sort((a, b) {
      final distA = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        a['latitude'] as double,
        a['longitude'] as double,
      );
      final distB = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        b['latitude'] as double,
        b['longitude'] as double,
      );
      return distA.compareTo(distB);
    });

    if (mounted) setState(() {});
  }

  Future<void> _unsaveCharger(String stationId) async {
    try {
      final user = ref.read(userProvider);
      if (user != null) {
        await _chargingService.unsaveCharger(
          userId: user.id,
          stationId: stationId,
        );
        await _loadSavedChargers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Charger removed from saved')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error removing charger: $e')));
      }
    }
  }

  String _getDistance(Map<String, dynamic> charger) {
    if (_currentPosition == null) return '';

    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      charger['latitude'] as double,
      charger['longitude'] as double,
    );

    if (distance < 1000) {
      return '${distance.round()} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadSavedChargers,
      child:
          _isLoading
              ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 420,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                          ),
                          const Gap(16),
                          Text(
                            'Loading saved chargers',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(6),
                          Text(
                            'Pulling your favorite stations and sorting them by distance.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
              : _savedChargers.isEmpty
              ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: 420,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.35,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PhosphorIcons.heartStraight(
                              PhosphorIconsStyle.duotone,
                            ),
                            size: 36,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Gap(16),
                        Text(
                          'Build your quick-access charger list',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Gap(8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Text(
                            'Save chargers you trust most so this tab becomes your go-to shortlist during a trip.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const Gap(14),
                        FilledButton.icon(
                          onPressed: _loadSavedChargers,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _savedChargers.length,
                itemBuilder: (context, index) {
                  final charger = _savedChargers[index];
                  final distance = _getDistance(charger);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Icon(
                        PhosphorIcons.plugCharging(PhosphorIconsStyle.duotone),
                        color: theme.colorScheme.primary,
                        size: 32,
                      ),
                      title: Text(
                        charger['name'] ?? 'Unknown Station',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Gap(4),
                          Text(
                            charger['address'] ?? 'No address',
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (distance.isNotEmpty) ...[
                            const Gap(4),
                            Row(
                              children: [
                                Icon(
                                  PhosphorIcons.mapPin(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                                const Gap(4),
                                Text(
                                  distance,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          PhosphorIcons.heartStraight(PhosphorIconsStyle.fill),
                          color: theme.colorScheme.error,
                        ),
                        onPressed: () => _unsaveCharger(charger['id']),
                      ),
                      isThreeLine: true,
                      onTap: () {
                        // Navigate to station details or show on map
                        // You can implement this based on your app's navigation
                      },
                    ),
                  );
                },
              ),
    );
  }
}
