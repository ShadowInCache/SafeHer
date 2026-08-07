// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contacts_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$contactsRepositoryHash() =>
    r'd23e2b8e872054960cd80cd969733b35f31417a2';

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
String _$contactsNotifierHash() => r'323b46d1001336e35150636ccf1e481496c7a424';

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
