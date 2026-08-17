// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authTokenStoreHash() => r'4466302cd24ab452e9e32738efbab777f27ce8bc';

/// See also [authTokenStore].
@ProviderFor(authTokenStore)
final authTokenStoreProvider = Provider<AuthTokenStore>.internal(
  authTokenStore,
  name: r'authTokenStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authTokenStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuthTokenStoreRef = ProviderRef<AuthTokenStore>;
String _$apiClientHash() => r'95bfd1fa791aa4d959a0abb642553151d981cf34';

/// See also [apiClient].
@ProviderFor(apiClient)
final apiClientProvider = Provider<ApiClient>.internal(
  apiClient,
  name: r'apiClientProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$apiClientHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ApiClientRef = ProviderRef<ApiClient>;
String _$backendWarmerHash() => r'1f8044913ea09dc9073c71fbcccc8b87b021706e';

/// Wakes a suspended backend before an emergency dispatch. See
/// [BackendWarmer] for why the SOS countdown is the right moment.
///
/// Copied from [backendWarmer].
@ProviderFor(backendWarmer)
final backendWarmerProvider = AutoDisposeProvider<BackendWarmer>.internal(
  backendWarmer,
  name: r'backendWarmerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$backendWarmerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BackendWarmerRef = AutoDisposeProviderRef<BackendWarmer>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
