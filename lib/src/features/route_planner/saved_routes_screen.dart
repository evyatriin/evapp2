import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';

import 'saved_route_model.dart';
import 'route_service.dart';

class SavedRoutesScreen extends StatelessWidget {
  const SavedRoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Routes'),
        centerTitle: true,
      ),
      body: const SavedRoutesList(),
    );
  }
}

class SavedRoutesList extends StatefulWidget {
  const SavedRoutesList({super.key});

  @override
  State<SavedRoutesList> createState() => _SavedRoutesListState();
}

class _SavedRoutesListState extends State<SavedRoutesList> {
  final _routeService = RouteService();
  List<SavedRoute> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() => _isLoading = true);
    try {
      final routes = await _routeService.getSavedRoutes();
      setState(() {
        _routes = routes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading routes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite(SavedRoute route) async {
    final newValue = !route.isFavorite;
    // Optimistic update
    setState(() {
      final index = _routes.indexWhere((r) => r.id == route.id);
      if (index != -1) {
        _routes[index] = route.copyWith(isFavorite: newValue);
      }
    });

    try {
      await _routeService.toggleFavorite(route.id, newValue);
    } catch (e) {
      // Revert on error
      setState(() {
        final index = _routes.indexWhere((r) => r.id == route.id);
        if (index != -1) {
          _routes[index] = route.copyWith(isFavorite: !newValue);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update favorite')),
        );
      }
    }
  }

  Future<void> _deleteRoute(SavedRoute route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Route'),
        content: const Text('Are you sure you want to delete this saved route?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Optimistic update
    final previousRoutes = List<SavedRoute>.from(_routes);
    setState(() {
      _routes.removeWhere((r) => r.id == route.id);
    });

    try {
      await _routeService.deleteRoute(route.id);
    } catch (e) {
      // Revert on error
      setState(() {
        _routes = previousRoutes;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete route')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadRoutes,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _routes.isEmpty
              ? ListView(
                  children: [
                    SizedBox(
                      height: 400,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(PhosphorIcons.path(PhosphorIconsStyle.duotone), size: 64, color: Colors.grey),
                          const Gap(16),
                          Text('No saved routes yet', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
                          const Gap(8),
                          FilledButton.tonal(
                            onPressed: () => context.go('/planner'),
                            child: const Text('Plan a Trip'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final route = _routes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          // Navigate to result screen with this route
                          context.push('/planner/result', extra: {
                            'routes': [route.routeData],
                            'vehicleId': route.vehicleId,
                            'startAddress': route.startAddress,
                            'endAddress': route.endAddress,
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      route.name,
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      route.isFavorite ? Icons.favorite : Icons.favorite_border,
                                      color: route.isFavorite ? Colors.red : null,
                                    ),
                                    onPressed: () => _toggleFavorite(route),
                                  ),
                                  PopupMenuButton(
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, color: Colors.red, size: 20),
                                            Gap(8),
                                            Text('Delete', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onSelected: (value) {
                                      if (value == 'delete') _deleteRoute(route);
                                    },
                                  ),
                                ],
                              ),
                              const Divider(),
                              const Gap(8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildInfoItem(context, PhosphorIcons.roadHorizon(PhosphorIconsStyle.regular), '${route.distanceKm.toStringAsFixed(1)} km'),
                                  _buildInfoItem(context, PhosphorIcons.clock(PhosphorIconsStyle.regular), '${(route.durationMin / 60).toStringAsFixed(1)} h'),
                                  _buildInfoItem(context, PhosphorIcons.plugCharging(PhosphorIconsStyle.regular), '${route.chargingStops} stops'),
                                ],
                              ),
                              const Gap(12),
                              Text(
                                'Saved on ${DateFormat.yMMMd().format(route.createdAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const Gap(4),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
