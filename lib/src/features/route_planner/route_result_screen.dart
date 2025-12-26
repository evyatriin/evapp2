import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:gap/gap.dart';

import 'route_model.dart';
import 'saved_route_model.dart';
import 'route_service.dart';
import 'route_planner_screen.dart'; // For TripSummarySheet
import '../authentication/auth_service.dart';

class RouteResultScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const RouteResultScreen({super.key, required this.extra});

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  late List<RouteModel> _routes;
  late RouteModel _selectedRoute;
  String? _vehicleId;
  String? _startAddress;
  String? _endAddress;
  
  static const LatLng _initialCenter = LatLng(17.3850, 78.4867);
  final _routeService = RouteService();
  final _authService = AuthService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _routes = widget.extra['routes'] as List<RouteModel>;
    _vehicleId = widget.extra['vehicleId'] as String?;
    _startAddress = widget.extra['startAddress'] as String?;
    _endAddress = widget.extra['endAddress'] as String?;
    
    if (_routes.isNotEmpty) {
      _selectedRoute = _routes.first;
    }
  }

  Future<void> _saveRoute() async {
    final userId = _authService.currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save routes')),
      );
      return;
    }

    // Safety check: Ensure route has stops
    if (_selectedRoute.stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Route has no stops. Please try planning the route again.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final savedRoute = SavedRoute(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temp ID, backend should generate
        userId: userId,
        name: '${_startAddress ?? "Start"} to ${_endAddress ?? "End"}',
        startLocation: _selectedRoute.stops.first.location,
        startAddress: _startAddress ?? 'Unknown Start',
        endLocation: _selectedRoute.stops.last.location,
        endAddress: _endAddress ?? 'Unknown Destination',
        vehicleId: _vehicleId,
        routeData: _selectedRoute,
        distanceKm: _selectedRoute.totalDistanceKm,
        durationMin: _selectedRoute.totalDurationMin.round(),
        chargingStops: _selectedRoute.stops.where((s) => s.type == StopType.charging).length,
        createdAt: DateTime.now(),
      );

      await _routeService.saveRoute(savedRoute);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Route Saved!'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map, size: 48, color: Colors.blue),
                Gap(16),
                Text('You earned +5 Points!'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving route: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _initialCenter,
              zoom: 8.0,
            ),
            polylines: {
              Polyline(
                polylineId: PolylineId(_selectedRoute.id),
                points: _selectedRoute.polyline
                    .map((p) => LatLng(p.latitude, p.longitude))
                    .toList(),
                color: theme.colorScheme.primary,
                width: 5,
              ),
            },
            markers: _selectedRoute.stops.map((stop) {
              return Marker(
                markerId: MarkerId(stop.name),
                position: LatLng(stop.location.latitude, stop.location.longitude),
                infoWindow: InfoWindow(
                  title: stop.name,
                  snippet: stop.type == StopType.charging ? 'Charge: ${stop.chargeDurationMin} min' : null,
                ),
                icon: stop.type == StopType.charging
                    ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
                    : stop.type == StopType.origin || stop.type == StopType.destination
                        ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
                        : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              );
            }).toSet(),
            onMapCreated: (controller) {
              // Fit bounds
              if (_selectedRoute.polyline.isNotEmpty) {
                 double minLat = _selectedRoute.polyline.first.latitude;
                 double maxLat = _selectedRoute.polyline.first.latitude;
                 double minLng = _selectedRoute.polyline.first.longitude;
                 double maxLng = _selectedRoute.polyline.first.longitude;

                 for (var p in _selectedRoute.polyline) {
                   if (p.latitude < minLat) minLat = p.latitude;
                   if (p.latitude > maxLat) maxLat = p.latitude;
                   if (p.longitude < minLng) minLng = p.longitude;
                   if (p.longitude > maxLng) maxLng = p.longitude;
                 }
                 
                 Future.delayed(const Duration(milliseconds: 500), () {
                   controller.animateCamera(CameraUpdate.newLatLngBounds(
                     LatLngBounds(
                       southwest: LatLng(minLat, minLng),
                       northeast: LatLng(maxLat, maxLng),
                     ),
                     50,
                   ));
                 });
              }
            },
          ),

          // Floating Header with Back Button + Route Selector
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Back Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: theme.colorScheme.onSurface,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  
                  // Divider
                  Container(
                    width: 1,
                    height: 32,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  
                  // Route Selector
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<RouteModel>(
                          value: _selectedRoute,
                          isExpanded: true,
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                          ),
                          items: _routes.asMap().entries.map((entry) {
                            final index = entry.key;
                            final route = entry.value;
                            final isSelected = route.id == _selectedRoute.id;
                            return DropdownMenuItem(
                              value: route,
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                          ? theme.colorScheme.primary 
                                          : theme.colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected 
                                              ? theme.colorScheme.onPrimary 
                                              : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Gap(10),
                                  Expanded(
                                    child: Text(
                                      route.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (RouteModel? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedRoute = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Trip Summary Sheet (Persistent Bottom)
          Align(
            alignment: Alignment.bottomCenter,
            child: TripSummarySheet(
              route: _selectedRoute, 
              onSave: _saveRoute,
              isSaving: _isSaving,
            ),
          ),
        ],
      ),
    );
  }
}
