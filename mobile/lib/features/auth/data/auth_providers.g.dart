// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authRepositoryHash() => r'7e8ef0f2095b13551bee11b4b4b9eaf586144680';

/// Selects the [AuthRepository] implementation.
///
/// * [AppConfig.useMockApi] -- fixture data, no network.
/// * [AppConfig.useFirebaseAuth] -- Firebase collects the credential and the
///   resulting ID token is exchanged for a backend JWT. Needed for Google and
///   Apple sign-in, and requires Firebase Authentication to be enabled in the
///   console.
/// * Otherwise -- `fastapi_app` serves email/password auth directly, which is
///   the default because it works without any console configuration.
///
/// Copied from [authRepository].
@ProviderFor(authRepository)
final authRepositoryProvider = AutoDisposeProvider<AuthRepository>.internal(
  authRepository,
  name: r'authRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AuthRepositoryRef = AutoDisposeProviderRef<AuthRepository>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
