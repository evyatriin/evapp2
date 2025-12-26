// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statistics_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(userStatistics)
const userStatisticsProvider = UserStatisticsFamily._();

final class UserStatisticsProvider
    extends
        $FunctionalProvider<
          AsyncValue<UserStatistics>,
          UserStatistics,
          FutureOr<UserStatistics>
        >
    with $FutureModifier<UserStatistics>, $FutureProvider<UserStatistics> {
  const UserStatisticsProvider._({
    required UserStatisticsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'userStatisticsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$userStatisticsHash();

  @override
  String toString() {
    return r'userStatisticsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<UserStatistics> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<UserStatistics> create(Ref ref) {
    final argument = this.argument as String;
    return userStatistics(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UserStatisticsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$userStatisticsHash() => r'15ada4b3e60681b6e4dfbe2262dda9c6a0726603';

final class UserStatisticsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<UserStatistics>, String> {
  const UserStatisticsFamily._()
    : super(
        retry: null,
        name: r'userStatisticsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UserStatisticsProvider call(String userId) =>
      UserStatisticsProvider._(argument: userId, from: this);

  @override
  String toString() => r'userStatisticsProvider';
}
