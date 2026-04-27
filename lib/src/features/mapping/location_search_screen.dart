import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';

import '../../common_widgets/location_autocomplete.dart';
import 'places_service.dart';
import 'stations_repository.dart';

class LocationSearchScreen extends ConsumerStatefulWidget {
  const LocationSearchScreen({super.key});

  @override
  ConsumerState<LocationSearchScreen> createState() =>
      _LocationSearchScreenState();
}

class _LocationSearchScreenState extends ConsumerState<LocationSearchScreen> {
  final _searchController = TextEditingController();
  final _placesService = PlacesService();
  bool _isLocating = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectPlace(String placeId) async {
    final location = await _placesService.getPlaceDetails(placeId);
    if (location == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find that location.')),
      );
      return;
    }

    ref.read(mapZoomProvider.notifier).update(11);
    ref
        .read(mapCenterProvider.notifier)
        .update(ll.LatLng(location.latitude, location.longitude));

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/');
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Turn on location services first.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is needed to search nearby.');
      }

      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

      if (!mounted) return;

      ref.read(mapZoomProvider.notifier).update(11);
      ref
          .read(mapCenterProvider.notifier)
          .update(ll.LatLng(position.latitude, position.longitude));
      if (Navigator.of(context).canPop()) {
        context.pop();
        return;
      }
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Area'),
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
                    'Search a place',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    'Search a city, area, or corridor and we will show chargers within roughly 20 km of that location.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Gap(16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: LocationAutocomplete(
                      controller: _searchController,
                      hintText: 'Search a city, area, or corridor',
                      onSelected: (selection) {
                        final placeId = selection['place_id'];
                        if (placeId != null && placeId.isNotEmpty) {
                          _selectPlace(placeId);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(16),
          FilledButton.icon(
            onPressed: _isLocating ? null : _useCurrentLocation,
            icon: _isLocating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(_isLocating ? 'Locating...' : 'Use my current location'),
          ),
        ],
      ),
    );
  }
}
