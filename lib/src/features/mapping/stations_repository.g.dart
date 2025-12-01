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

String _$stationsHash() => r'd625556549f020d783ea589b00a82327c865eebc';
