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
    r'a35687d7184b57e16524bfa0cfe64afa25c819d8';

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

String _$mapCenterHash() => r'7680730805d74a56cef3ff79aa3604e4e6f34947';

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

String _$stationsHash() => r'dedb3ca9f534046e65df62c591456a31a7529a51';
