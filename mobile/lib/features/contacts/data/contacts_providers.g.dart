// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contacts_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$contactsRepositoryHash() =>
    r'9328fd428db2605f57c1a6fa8bac63da5921bf18';

/// See also [contactsRepository].
@ProviderFor(contactsRepository)
final contactsRepositoryProvider =
    AutoDisposeProvider<ContactsRepository>.internal(
      contactsRepository,
      name: r'contactsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$contactsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ContactsRepositoryRef = AutoDisposeProviderRef<ContactsRepository>;
String _$alertChannelsHash() => r'2e3c8d8c3940830d216ad77c9058fb399e6d3c4a';

/// Which emergency channels the server can deliver on.
///
/// Falls back to optimistic on failure: a wrongly-shown "can't be reached"
/// warning would train users to ignore a warning that only helps if it is
/// rare and true.
///
/// Copied from [alertChannels].
@ProviderFor(alertChannels)
final alertChannelsProvider = AutoDisposeFutureProvider<AlertChannels>.internal(
  alertChannels,
  name: r'alertChannelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$alertChannelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AlertChannelsRef = AutoDisposeFutureProviderRef<AlertChannels>;
String _$contactsNotifierHash() => r'68f785697131f5f1a41466b1028f48e717f5d42f';

/// The single source of truth for the app's emergency contacts — Settings,
/// Emergency, Search, and Profile all watch this instead of keeping their
/// own copies, so adding/removing/reordering a contact anywhere is
/// immediately reflected everywhere.
///
/// Mutations made while offline apply optimistically to local state and
/// are queued (see `OfflineQueueService`) rather than failing outright —
/// they replay automatically the next time connectivity comes back.
///
/// Copied from [ContactsNotifier].
@ProviderFor(ContactsNotifier)
final contactsNotifierProvider =
    AsyncNotifierProvider<ContactsNotifier, List<Contact>>.internal(
      ContactsNotifier.new,
      name: r'contactsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$contactsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ContactsNotifier = AsyncNotifier<List<Contact>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
