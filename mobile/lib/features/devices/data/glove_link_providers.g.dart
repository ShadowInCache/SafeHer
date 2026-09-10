// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glove_link_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$gloveLinkHash() => r'df0b3fcee97773c26447fafdd2390ee8bfaf13d6';

/// Listens to a connected SafeHer glove and holds what it reports.
///
/// **The gap this closes.** Pairing worked and the model ran on the ESP32,
/// but nothing in the app ever subscribed to a characteristic -- so the glove
/// notified its classifications into a socket with no listener, and the
/// device card showed hardcoded zeros beside a device that was genuinely
/// connected.
///
/// Subscription follows the pairing stage rather than being started by hand:
/// a link that drops and is re-established has to resubscribe, and leaving
/// that to a caller is how it ends up done in one place and forgotten in
/// another.
///
/// `keepAlive` because the glove is not tied to a screen. It keeps reporting
/// while the user is on Home, in Settings, or has the app in the background,
/// and a link torn down by navigation would be a safety device that only
/// works while you are looking at it.
///
/// Copied from [GloveLink].
@ProviderFor(GloveLink)
final gloveLinkProvider = NotifierProvider<GloveLink, GloveLinkState>.internal(
  GloveLink.new,
  name: r'gloveLinkProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$gloveLinkHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$GloveLink = Notifier<GloveLinkState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
