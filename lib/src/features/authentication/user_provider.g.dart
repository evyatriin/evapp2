// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(User)
const userProvider = UserProvider._();

final class UserProvider extends $NotifierProvider<User, UserProfile?> {
  const UserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userHash();

  @$internal
  @override
  User create() => User();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserProfile? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserProfile?>(value),
    );
  }
}

String _$userHash() => r'e56c57e2b33b8a8f63384677f77a9ea36c633c6b';

abstract class _$User extends $Notifier<UserProfile?> {
  UserProfile? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<UserProfile?, UserProfile?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UserProfile?, UserProfile?>,
              UserProfile?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
