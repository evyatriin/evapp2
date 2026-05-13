// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stations_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(stationsRepository)
const stationsRepositoryProvider = StationsRepositoryProvider._();

final class StationsRepositoryProvider
    extends
        $FunctionalProvider<
          StationsRepository,
          StationsRepository,
          StationsRepository
        >
    with $Provider<StationsRepository> {
  const StationsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stationsRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stationsRepositoryHash();

  @$internal
  @override
  $ProviderElement<StationsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StationsRepository create(Ref ref) {
    return stationsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StationsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StationsRepository>(value),
    );
  }
}

String _$stationsRepositoryHash() =>
    r'0b70af19d83d478009969ad38e481d8e5d977079';

@ProviderFor(MapCenter)
const mapCenterProvider = MapCenterProvider._();

final class MapCenterProvider extends $NotifierProvider<MapCenter, LatLng> {
  const MapCenterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapCenterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapCenterHash();

  @$internal
  @override
  MapCenter create() => MapCenter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LatLng value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LatLng>(value),
    );
  }
}

String _$mapCenterHash() => r'9c87207bc06425e6eb36c2d0ac35f50f91878405';

abstract class _$MapCenter extends $Notifier<LatLng> {
  LatLng build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<LatLng, LatLng>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LatLng, LatLng>,
              LatLng,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(MapZoom)
const mapZoomProvider = MapZoomProvider._();

final class MapZoomProvider extends $NotifierProvider<MapZoom, double> {
  const MapZoomProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapZoomProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapZoomHash();

  @$internal
  @override
  MapZoom create() => MapZoom();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(double value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<double>(value),
    );
  }
}

String _$mapZoomHash() => r'57b724ce074f21226df37b5742d0b9c0ab7ad752';

abstract class _$MapZoom extends $Notifier<double> {
  double build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<double, double>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<double, double>,
              double,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(ConnectorFilter)
const connectorFilterProvider = ConnectorFilterProvider._();

final class ConnectorFilterProvider
    extends $NotifierProvider<ConnectorFilter, Set<String>> {
  const ConnectorFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectorFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectorFilterHash();

  @$internal
  @override
  ConnectorFilter create() => ConnectorFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$connectorFilterHash() => r'89b9b9d98468821d5324e5bbc69d90c86d3b2afa';

abstract class _$ConnectorFilter extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(SpeedFilter)
const speedFilterProvider = SpeedFilterProvider._();

final class SpeedFilterProvider
    extends $NotifierProvider<SpeedFilter, Set<String>> {
  const SpeedFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'speedFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$speedFilterHash();

  @$internal
  @override
  SpeedFilter create() => SpeedFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$speedFilterHash() => r'e389947777e26684328cff4d5d985d90a176d3ce';

abstract class _$SpeedFilter extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(PriceFilter)
const priceFilterProvider = PriceFilterProvider._();

final class PriceFilterProvider
    extends $NotifierProvider<PriceFilter, Set<String>> {
  const PriceFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'priceFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$priceFilterHash();

  @$internal
  @override
  PriceFilter create() => PriceFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$priceFilterHash() => r'04a977b0d5e12f3c1a2953270a3af076c74a8f93';

abstract class _$PriceFilter extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(AvailableNowFilter)
const availableNowFilterProvider = AvailableNowFilterProvider._();

final class AvailableNowFilterProvider
    extends $NotifierProvider<AvailableNowFilter, bool> {
  const AvailableNowFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableNowFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableNowFilterHash();

  @$internal
  @override
  AvailableNowFilter create() => AvailableNowFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$availableNowFilterHash() =>
    r'29d25a0ed067cf658372e80f4cba0216f3db0d83';

abstract class _$AvailableNowFilter extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(AccessFilter)
const accessFilterProvider = AccessFilterProvider._();

final class AccessFilterProvider
    extends $NotifierProvider<AccessFilter, Set<String>> {
  const AccessFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accessFilterProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accessFilterHash();

  @$internal
  @override
  AccessFilter create() => AccessFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$accessFilterHash() => r'5fff750948aeddf436aa6f91667885e957228406';

abstract class _$AccessFilter extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(stations)
const stationsProvider = StationsProvider._();

final class StationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<StationModel>>,
          List<StationModel>,
          FutureOr<List<StationModel>>
        >
    with
        $FutureModifier<List<StationModel>>,
        $FutureProvider<List<StationModel>> {
  const StationsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'stationsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$stationsHash();

  @$internal
  @override
  $FutureProviderElement<List<StationModel>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<StationModel>> create(Ref ref) {
    return stations(ref);
  }
}

String _$stationsHash() => r'1e4e20dc72147675bb88497b25e3c9b32740310e';
