// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fake_stations_repository.dart';

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
          FakeStationsRepository,
          FakeStationsRepository,
          FakeStationsRepository
        >
    with $Provider<FakeStationsRepository> {
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
  $ProviderElement<FakeStationsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FakeStationsRepository create(Ref ref) {
    return stationsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FakeStationsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FakeStationsRepository>(value),
    );
  }
}

String _$stationsRepositoryHash() =>
    r'b95aa7a00375cf359124f33cdafe9819ab4723bf';

@ProviderFor(stations)
const stationsProvider = StationsProvider._();

final class StationsProvider
    extends
        $FunctionalProvider<
          List<StationModel>,
          List<StationModel>,
          List<StationModel>
        >
    with $Provider<List<StationModel>> {
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
  $ProviderElement<List<StationModel>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<StationModel> create(Ref ref) {
    return stations(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<StationModel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<StationModel>>(value),
    );
  }
}

String _$stationsHash() => r'0880809d2d34b5d224f1050cce9e87fb654df4f4';
