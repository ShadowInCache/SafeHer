// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emergency_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$emergencyRepositoryHash() =>
    r'f48fccd9b64a6d22a74e53f1b8b2adfbb046bc5e';

/// See also [emergencyRepository].
@ProviderFor(emergencyRepository)
final emergencyRepositoryProvider =
    AutoDisposeProvider<EmergencyRepository>.internal(
      emergencyRepository,
      name: r'emergencyRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$emergencyRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EmergencyRepositoryRef = AutoDisposeProviderRef<EmergencyRepository>;
String _$emergencyContactsHash() => r'dcaaa10d566812779464c5d93deb69a01bebfa4d';

/// See also [emergencyContacts].
@ProviderFor(emergencyContacts)
final emergencyContactsProvider =
    AutoDisposeFutureProvider<List<EmergencyContactSummary>>.internal(
      emergencyContacts,
      name: r'emergencyContactsProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$emergencyContactsHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EmergencyContactsRef =
    AutoDisposeFutureProviderRef<List<EmergencyContactSummary>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
