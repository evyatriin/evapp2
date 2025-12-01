import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route saved successfully!')),
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: theme.colorScheme.surface,
            child: BackButton(color: theme.colorScheme.onSurface),
          ),
        ),
      ),
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
                color: Colors.blue,
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

          // Plan Selection Dropdown (Floating Top)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<RouteModel>(
                    value: _selectedRoute,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    items: _routes.map((route) {
                      return DropdownMenuItem(
                        value: route,
                        child: Text(
                          route.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
