import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend_service.dart';
import 'vehicle_model.dart';
import 'vehicle_template_model.dart';

class VehicleService {
  VehicleService() : _supabase = Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _vehiclesCachePrefix = 'cached_vehicles_';
  static const String _vehiclesHashPrefix = 'cached_vehicles_hash_';
  static const String _vehiclesPreferenceKey = 'vehicles';
  static const String _primaryVehicleIdPreferenceKey = 'primary_vehicle_id';

  String? getCurrentUserId() => _supabase.auth.currentUser?.id;

  Future<List<VehicleProfile>> getCachedVehicles([String? userId]) async {
    final resolvedUserId = userId ?? getCurrentUserId();
    if (resolvedUserId == null) return [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_vehiclesCacheKey(resolvedUserId));
      if (cachedJson == null || cachedJson.isEmpty) {
        return [];
      }

      final List<dynamic> data = json.decode(cachedJson) as List<dynamic>;
      return data
          .map((item) => VehicleProfile.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error reading vehicle cache: $e');
      return [];
    }
  }

  Future<void> _cacheVehicles(
    String userId,
    List<VehicleProfile> vehicles,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(vehicles.map((v) => v.toJson()).toList());
      await prefs.setString(_vehiclesCacheKey(userId), jsonData);
      await prefs.setString(_vehiclesHashKey(userId), _computeHash(vehicles));
    } catch (e) {
      debugPrint('Error caching vehicles: $e');
    }
  }

  Future<void> clearCache([String? userId]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (userId != null) {
        await prefs.remove(_vehiclesCacheKey(userId));
        await prefs.remove(_vehiclesHashKey(userId));
        return;
      }

      final keys = prefs.getKeys().where(
        (key) =>
            key.startsWith(_vehiclesCachePrefix) ||
            key.startsWith(_vehiclesHashPrefix),
      );

      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('Error clearing vehicle cache: $e');
    }
  }

  Future<List<VehicleProfile>> fetchVehiclesWithCache(String userId) async {
    final cachedVehicles = await getCachedVehicles(userId);

    try {
      final remoteVehicles = await fetchVehicles(userId);
      await _cacheVehicles(userId, remoteVehicles);
      return remoteVehicles;
    } catch (e) {
      debugPrint('Error fetching remote vehicles, using cache: $e');
      return cachedVehicles;
    }
  }

  Future<List<VehicleProfile>> fetchVehicles(String userId) async {
    var vehicles = await _fetchRemoteVehicles(userId);
    if (vehicles.isEmpty) {
      final legacyVehicles = await _loadLegacyPreferenceVehicles(userId);
      if (legacyVehicles.isNotEmpty) {
        vehicles = await _migrateLegacyVehicles(userId, legacyVehicles);
      }
    }

    final normalized = await _normalizeRemoteVehicles(vehicles);
    await _cacheVehicles(userId, normalized);
    return normalized;
  }

  Future<VehicleProfile?> addVehicle(VehicleProfile vehicle) async {
    final userId = getCurrentUserId();
    if (userId == null) {
      throw Exception('Please login to add a vehicle');
    }

    final vehicles = await fetchVehicles(userId);

    final normalizedVehicle = vehicle.copyWith(
      id: vehicle.id,
      userId: userId,
      isPrimary: vehicles.isEmpty || vehicle.isPrimary,
    );

    final addedVehicle = await _createRemoteVehicle(normalizedVehicle);
    await fetchVehicles(userId);
    return addedVehicle;
  }

  Future<VehicleProfile?> updateVehicle(VehicleProfile vehicle) async {
    final userId = getCurrentUserId();
    if (userId == null) {
      throw Exception('Please login to update a vehicle');
    }

    final existingVehicles = await fetchVehicles(userId);
    if (!existingVehicles.any((item) => item.id == vehicle.id)) {
      throw Exception('Vehicle not found');
    }

    final updatedVehicle = await _updateRemoteVehicle(
      vehicle.copyWith(userId: userId),
    );
    await fetchVehicles(userId);
    return updatedVehicle;
  }

  Future<bool> deleteVehicle(String vehicleId) async {
    final userId = getCurrentUserId();
    if (userId == null) {
      throw Exception('Please login to delete a vehicle');
    }

    final existingVehicles = await fetchVehicles(userId);
    if (!existingVehicles.any((vehicle) => vehicle.id == vehicleId)) {
      return false;
    }

    await BackendService.delete('/api/vehicles/$vehicleId');
    await fetchVehicles(userId);

    return true;
  }

  Future<bool> setPrimaryVehicle(String vehicleId) async {
    final userId = getCurrentUserId();
    if (userId == null) {
      throw Exception('Please login to update your primary vehicle');
    }

    final existingVehicles = await fetchVehicles(userId);
    if (!existingVehicles.any((vehicle) => vehicle.id == vehicleId)) {
      return false;
    }

    await BackendService.put('/api/vehicles/$vehicleId/primary', body: {});
    await fetchVehicles(userId);

    return true;
  }

  Future<List<VehicleProfile>> _fetchRemoteVehicles(String userId) async {
    final response = await BackendService.get(
      '/api/vehicles',
      queryParams: {'user_id': userId},
    );
    return _parseVehicleList(response);
  }

  Future<VehicleProfile> _createRemoteVehicle(VehicleProfile vehicle) async {
    final response = await BackendService.post(
      '/api/vehicles',
      body: _vehicleCreatePayload(vehicle),
    );
    return _parseVehicle(response);
  }

  Future<VehicleProfile> _updateRemoteVehicle(VehicleProfile vehicle) async {
    final response = await BackendService.put(
      '/api/vehicles/${vehicle.id}',
      body: _vehicleUpdatePayload(vehicle),
    );
    return _parseVehicle(response);
  }

  Future<List<VehicleProfile>> _normalizeRemoteVehicles(
    List<VehicleProfile> vehicles,
  ) async {
    if (vehicles.isEmpty) return const [];

    if (vehicles.any((vehicle) => vehicle.isPrimary)) {
      return _normalizeVehicles(vehicles, null);
    }

    final primaryVehicle = await _setRemotePrimary(vehicles.first.id);
    return [
      for (final vehicle in vehicles)
        vehicle.copyWith(isPrimary: vehicle.id == primaryVehicle.id),
    ];
  }

  Future<VehicleProfile> _setRemotePrimary(String vehicleId) async {
    final response = await BackendService.put(
      '/api/vehicles/$vehicleId/primary',
      body: {},
    );
    return _parseVehicle(response);
  }

  Future<List<VehicleProfile>> _loadLegacyPreferenceVehicles(
    String userId,
  ) async {
    final response =
        await _supabase
            .from('profiles')
            .select('preferences')
            .eq('id', userId)
            .maybeSingle();

    if (response == null) {
      return const [];
    }

    final preferences = response['preferences'];
    if (preferences is Map) {
      final rawVehicles = preferences[_vehiclesPreferenceKey];
      final primaryVehicleId =
          preferences[_primaryVehicleIdPreferenceKey] as String?;

      if (rawVehicles is! List) {
        return const [];
      }

      final vehicles =
          rawVehicles
              .whereType<Map>()
              .map(
                (item) =>
                    VehicleProfile.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList();

      return _normalizeVehicles(vehicles, primaryVehicleId);
    }

    return const [];
  }

  Future<List<VehicleProfile>> _migrateLegacyVehicles(
    String userId,
    List<VehicleProfile> legacyVehicles,
  ) async {
    final migrated = <VehicleProfile>[];
    for (final vehicle in legacyVehicles) {
      final created = await _createRemoteVehicle(
        vehicle.copyWith(userId: userId),
      );
      migrated.add(created);
    }

    return _normalizeRemoteVehicles(migrated);
  }

  List<VehicleProfile> _parseVehicleList(dynamic response) {
    final vehicles = response as List<dynamic>;
    return vehicles
        .map((item) => _parseVehicle(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  VehicleProfile _parseVehicle(dynamic response) {
    return VehicleProfile.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Map<String, dynamic> _vehicleCreatePayload(VehicleProfile vehicle) {
    return {
      'user_id': vehicle.userId,
      'brand': vehicle.brand,
      'model': vehicle.model,
      'variant': vehicle.variant,
      'range_efficiency': vehicle.rangeEfficiency,
      'image_url': vehicle.imageUrl,
      'photo_url': vehicle.photoUrl,
      'preferred_charging_networks': vehicle.preferredChargingNetworks,
      'is_primary': vehicle.isPrimary,
    };
  }

  Map<String, dynamic> _vehicleUpdatePayload(VehicleProfile vehicle) {
    return {
      'brand': vehicle.brand,
      'model': vehicle.model,
      'variant': vehicle.variant,
      'range_efficiency': vehicle.rangeEfficiency,
      'image_url': vehicle.imageUrl,
      'photo_url': vehicle.photoUrl,
      'preferred_charging_networks': vehicle.preferredChargingNetworks,
      'is_primary': vehicle.isPrimary,
    };
  }

  Future<List<VehicleTemplate>> fetchVehicleTemplates() async {
    try {
      final response = await BackendService.get('/api/vehicles/templates');
      final templates = response as List<dynamic>;
      if (templates.isEmpty) {
        return _fallbackTemplates;
      }

      final remoteTemplates =
          templates
              .map(
                (item) => VehicleTemplate.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
      return _mergeTemplates(remoteTemplates, _fallbackTemplates);
    } catch (e) {
      debugPrint('Error fetching vehicle templates: $e');
      return _fallbackTemplates;
    }
  }

  List<VehicleProfile> _normalizeVehicles(
    List<VehicleProfile> vehicles,
    String? primaryVehicleId,
  ) {
    if (vehicles.isEmpty) return const [];

    final resolvedPrimaryId =
        primaryVehicleId ??
        vehicles
            .cast<VehicleProfile?>()
            .firstWhere(
              (vehicle) => vehicle?.isPrimary == true,
              orElse: () => vehicles.first,
            )
            ?.id ??
        vehicles.first.id;

    return [
      for (final vehicle in vehicles)
        vehicle.copyWith(isPrimary: vehicle.id == resolvedPrimaryId),
    ];
  }

  String _computeHash(List<VehicleProfile> vehicles) {
    final normalized =
        vehicles
            .map(
              (vehicle) => {
                'id': vehicle.id,
                'brand': vehicle.brand,
                'model': vehicle.model,
                'variant': vehicle.variant,
                'range_efficiency': vehicle.rangeEfficiency,
                'is_primary': vehicle.isPrimary,
              },
            )
            .toList()
          ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    return json.encode(normalized);
  }

  String _vehiclesCacheKey(String userId) => '$_vehiclesCachePrefix$userId';

  String _vehiclesHashKey(String userId) => '$_vehiclesHashPrefix$userId';
}

List<VehicleTemplate> _mergeTemplates(
  List<VehicleTemplate> primary,
  List<VehicleTemplate> fallback,
) {
  final merged = <String, VehicleTemplate>{};

  for (final template in fallback) {
    merged[_templateKey(template)] = template;
  }

  for (final template in primary) {
    merged[_templateKey(template)] = template;
  }

  final values = merged.values.toList();
  values.sort((a, b) {
    final brandCompare = a.brand.compareTo(b.brand);
    if (brandCompare != 0) return brandCompare;
    final modelCompare = a.model.compareTo(b.model);
    if (modelCompare != 0) return modelCompare;
    return a.variant.compareTo(b.variant);
  });
  return values;
}

String _templateKey(VehicleTemplate template) {
  return '${template.brand}|${template.model}|${template.variant}'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9|]+'), '-');
}

double _rangeToEfficiency(double rangeKm) {
  final efficiency = rangeKm / 400.0;
  return efficiency.clamp(0.55, 1.2);
}

VehicleTemplate _template({
  required String brand,
  required String model,
  required String variant,
  required double rangeKm,
  String? imageUrl,
  List<String>? preferredChargingNetworks,
}) {
  final normalizedId = '$brand-$model-$variant'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  return VehicleTemplate(
    id: normalizedId,
    brand: brand,
    model: model,
    variant: variant,
    rangeEfficiency: _rangeToEfficiency(rangeKm),
    imageUrl: imageUrl ?? _vehicleImageUrl(brand, model),
    preferredChargingNetworks:
        preferredChargingNetworks ?? _defaultNetworksForBrand(brand),
  );
}

String _vehicleImageUrl(String brand, String model) {
  final key = '$brand|$model'.toLowerCase();
  switch (key) {
    case 'tata|nexon ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/141867/nexon-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80';
    case 'tata|tigor ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/115777/tigor-ev-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80';
    case 'tata|punch ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/163701/punch-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80';
    case 'tata|tiago ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/131129/tiago-ev-exterior-right-front-three-quarter-14.jpeg?isig=0&q=80';
    case 'tata|curvv ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/139651/curvv-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'tata|harrier ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/139187/harrier-ev-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'tata|sierra ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/187421/sierra-ev-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'mg|comet ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/146499/comet-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80';
    case 'mg|zs ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/113531/zs-ev-exterior-right-front-three-quarter-2.jpeg?isig=0&q=80';
    case 'mg|cyberster':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/139949/cyberster-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'mahindra|be 6':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/181095/be-6e-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'mahindra|xev 9e':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/181097/xev-9e-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'mahindra|xuv400':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/143867/xuv400-exterior-right-front-three-quarter-3.jpeg?isig=0&q=80';
    case 'hyundai|kona electric':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/40530/kona-electric-exterior-right-front-three-quarter-16.jpeg?isig=0&q=80';
    case 'hyundai|ioniq 5':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/136217/ioniq-5-exterior-right-front-three-quarter-4.jpeg?isig=0&q=80';
    case 'hyundai|creta ev':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/171213/creta-electric-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'byd|atto 3':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/51940/atto-3-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    case 'byd|sealion 7':
      return 'https://imgd.aeplcdn.com/1056x594/n/cw/ec/175893/sealion-7-exterior-right-front-three-quarter.jpeg?isig=0&q=80';
    default:
      return '';
  }
}

List<String> _defaultNetworksForBrand(String brand) {
  switch (brand.toLowerCase()) {
    case 'tata':
      return const ['Tata Power', 'Statiq'];
    case 'mg':
      return const ['Fortum', 'Tata Power'];
    case 'mahindra':
      return const ['ChargeZone', 'Jio-bp'];
    case 'hyundai':
      return const ['ChargeZone', 'Shell Recharge'];
    case 'byd':
      return const ['ChargeZone', 'Statiq'];
    case 'citroen':
      return const ['ChargeZone', 'Jio-bp'];
    case 'bmw':
    case 'mercedes-benz':
    case 'audi':
    case 'volvo':
    case 'kia':
    case 'porsche':
    case 'rolls-royce':
    case 'lexus':
    case 'jaguar':
      return const ['Shell Recharge', 'ChargeZone'];
    case 'vinfast':
      return const ['ChargeZone', 'Statiq'];
    case 'mini':
      return const ['ChargeZone', 'Shell Recharge'];
    case 'tesla':
      return const ['Supercharger'];
    case 'nissan':
      return const ['ChargeZone'];
    case 'maruti suzuki':
    case 'toyota':
      return const ['Tata Power', 'ChargeZone'];
    default:
      return const [];
  }
}

final List<VehicleTemplate> _fallbackTemplates = [
  _template(
    brand: 'Tata',
    model: 'Nexon EV',
    variant: 'Creative MR',
    rangeKm: 325,
  ),
  _template(
    brand: 'Tata',
    model: 'Nexon EV',
    variant: 'Creative LR',
    rangeKm: 465,
  ),
  _template(
    brand: 'Tata',
    model: 'Nexon EV',
    variant: 'Fearless MR',
    rangeKm: 325,
  ),
  _template(
    brand: 'Tata',
    model: 'Nexon EV',
    variant: 'Fearless LR',
    rangeKm: 465,
  ),
  _template(
    brand: 'Tata',
    model: 'Punch EV',
    variant: 'Smart MR',
    rangeKm: 315,
  ),
  _template(
    brand: 'Tata',
    model: 'Punch EV',
    variant: 'Empowered LR',
    rangeKm: 421,
  ),
  _template(brand: 'Tata', model: 'Tiago EV', variant: 'XE MR', rangeKm: 250),
  _template(brand: 'Tata', model: 'Tiago EV', variant: 'XZ+ LR', rangeKm: 315),
  _template(brand: 'Tata', model: 'Tigor EV', variant: 'XE', rangeKm: 306),
  _template(brand: 'Tata', model: 'Tigor EV', variant: 'XZ+', rangeKm: 306),
  _template(
    brand: 'Tata',
    model: 'Curvv EV',
    variant: 'Creative',
    rangeKm: 450,
  ),
  _template(
    brand: 'Tata',
    model: 'Curvv EV',
    variant: 'Accomplished LR',
    rangeKm: 500,
  ),
  _template(
    brand: 'Tata',
    model: 'Harrier EV',
    variant: 'Adventure',
    rangeKm: 500,
  ),
  _template(
    brand: 'Tata',
    model: 'Harrier EV',
    variant: 'Empowered AWD',
    rangeKm: 550,
  ),
  _template(brand: 'Tata', model: 'Sierra EV', variant: 'Smart', rangeKm: 450),
  _template(
    brand: 'Tata',
    model: 'Sierra EV',
    variant: 'Adventure',
    rangeKm: 480,
  ),
  _template(
    brand: 'Tata',
    model: 'Sierra EV',
    variant: 'Accomplished AWD',
    rangeKm: 500,
  ),
  _template(brand: 'MG', model: 'Comet EV', variant: 'Executive', rangeKm: 230),
  _template(brand: 'MG', model: 'Comet EV', variant: 'Excite', rangeKm: 230),
  _template(brand: 'MG', model: 'Comet EV', variant: 'Exclusive', rangeKm: 230),
  _template(brand: 'MG', model: 'ZS EV', variant: 'Executive', rangeKm: 461),
  _template(brand: 'MG', model: 'ZS EV', variant: 'Exclusive', rangeKm: 461),
  _template(brand: 'MG', model: 'Cyberster', variant: 'RWD', rangeKm: 500),
  _template(
    brand: 'MG',
    model: 'Cyberster',
    variant: 'AWD Performance',
    rangeKm: 580,
  ),
  _template(brand: 'Mahindra', model: 'XUV400', variant: 'EC', rangeKm: 375),
  _template(brand: 'Mahindra', model: 'XUV400', variant: 'EL', rangeKm: 456),
  _template(
    brand: 'Mahindra',
    model: 'BE 6',
    variant: 'Pack One',
    rangeKm: 557,
  ),
  _template(
    brand: 'Mahindra',
    model: 'BE 6',
    variant: 'Pack Three',
    rangeKm: 683,
  ),
  _template(
    brand: 'Mahindra',
    model: 'XEV 9e',
    variant: 'Pack One',
    rangeKm: 542,
  ),
  _template(
    brand: 'Mahindra',
    model: 'XEV 9e',
    variant: 'Pack Three AWD',
    rangeKm: 656,
  ),
  _template(
    brand: 'Hyundai',
    model: 'IONIQ 5',
    variant: 'Long Range',
    rangeKm: 631,
  ),
  _template(
    brand: 'Hyundai',
    model: 'Kona Electric',
    variant: 'Premium',
    rangeKm: 452,
  ),
  _template(brand: 'Hyundai', model: 'Creta EV', variant: 'Base', rangeKm: 450),
  _template(brand: 'BYD', model: 'Atto 3', variant: 'Dynamic', rangeKm: 521),
  _template(brand: 'BYD', model: 'Atto 3', variant: 'Superior', rangeKm: 521),
  _template(brand: 'BYD', model: 'Sealion 7', variant: 'Premium', rangeKm: 567),
  _template(
    brand: 'BYD',
    model: 'Sealion 7',
    variant: 'Performance AWD',
    rangeKm: 542,
  ),
  _template(brand: 'Citroen', model: 'eC3', variant: 'Feel', rangeKm: 320),
  _template(brand: 'BMW', model: 'i4', variant: 'eDrive35', rangeKm: 483),
  _template(brand: 'BMW', model: 'iX', variant: 'xDrive50', rangeKm: 635),
  _template(
    brand: 'Mercedes-Benz',
    model: 'EQA',
    variant: '250+',
    rangeKm: 560,
  ),
  _template(
    brand: 'Mercedes-Benz',
    model: 'EQB',
    variant: '300 4MATIC',
    rangeKm: 423,
  ),
  _template(brand: 'Mercedes-Benz', model: 'EQS', variant: '580', rangeKm: 857),
  _template(
    brand: 'Audi',
    model: 'Q8 e-tron',
    variant: '55 quattro',
    rangeKm: 600,
  ),
  _template(
    brand: 'Audi',
    model: 'e-tron GT',
    variant: 'Quattro',
    rangeKm: 500,
  ),
  _template(brand: 'Audi', model: 'e-tron GT', variant: 'RS', rangeKm: 488),
  _template(
    brand: 'Volvo',
    model: 'XC40 Recharge',
    variant: 'Ultimate AWD',
    rangeKm: 592,
  ),
  _template(
    brand: 'Volvo',
    model: 'C40 Recharge',
    variant: 'Ultimate AWD',
    rangeKm: 530,
  ),
  _template(brand: 'Kia', model: 'EV6', variant: 'GT Line AWD', rangeKm: 708),
  _template(brand: 'Kia', model: 'EV9', variant: 'GT Line AWD', rangeKm: 541),
  _template(brand: 'VinFast', model: 'VF 6', variant: 'Eco', rangeKm: 399),
  _template(brand: 'VinFast', model: 'VF 7', variant: 'Plus AWD', rangeKm: 431),
  _template(brand: 'VinFast', model: 'VF 8', variant: 'Eco', rangeKm: 471),
  _template(brand: 'VinFast', model: 'VF 8', variant: 'Plus AWD', rangeKm: 457),
  _template(brand: 'VinFast', model: 'VF 9', variant: 'Plus AWD', rangeKm: 531),
  _template(brand: 'VinFast', model: 'VF MPV 7', variant: 'Eco', rangeKm: 400),
  _template(brand: 'VinFast', model: 'VF MPV 7', variant: 'Plus', rangeKm: 450),
  _template(brand: 'VinFast', model: 'VF3', variant: 'Base', rangeKm: 200),
  _template(brand: 'Mini', model: 'Cooper SE', variant: '3-Door', rangeKm: 270),
  _template(brand: 'Porsche', model: 'Taycan', variant: 'RWD', rangeKm: 484),
  _template(
    brand: 'Porsche',
    model: 'Taycan',
    variant: 'Turbo S',
    rangeKm: 412,
  ),
  _template(
    brand: 'Rolls-Royce',
    model: 'Spectre',
    variant: 'Coupe',
    rangeKm: 530,
  ),
  _template(brand: 'Lexus', model: 'UX300e', variant: 'Luxury', rangeKm: 315),
  _template(brand: 'Tesla', model: 'Model 3', variant: 'RWD', rangeKm: 513),
  _template(
    brand: 'Tesla',
    model: 'Model 3',
    variant: 'Performance',
    rangeKm: 547,
  ),
  _template(
    brand: 'Tesla',
    model: 'Model Y',
    variant: 'Long Range AWD',
    rangeKm: 661,
  ),
  _template(brand: 'Nissan', model: 'Leaf', variant: 'e+', rangeKm: 385),
  _template(brand: 'Jaguar', model: 'I-Pace', variant: 'HSE', rangeKm: 470),
  _template(
    brand: 'Maruti Suzuki',
    model: 'e Vitara',
    variant: 'Delta 49kWh',
    rangeKm: 400,
  ),
  _template(
    brand: 'Maruti Suzuki',
    model: 'e Vitara',
    variant: 'Zeta 60kWh',
    rangeKm: 543,
  ),
  _template(
    brand: 'Maruti Suzuki',
    model: 'e Vitara',
    variant: 'Alpha 60kWh',
    rangeKm: 550,
  ),
  _template(
    brand: 'Toyota',
    model: 'Urban Cruiser EV',
    variant: 'Standard',
    rangeKm: 500,
  ),
];
