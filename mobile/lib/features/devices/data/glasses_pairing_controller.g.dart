// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glasses_pairing_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$glassesPairingHash() => r'cbf8e430954d21e04b9036f424b75cbe789849a4';

/// Pairs the glasses by address, and proves the address before saving it.
///
/// ## Why this exists at all
///
/// The whole weapon-detection path — the MJPEG parser, the detector, the
/// scorer, the server fallback — was built and tested while nothing anywhere
/// called `setGlassesHost`. `glassesStreamUri` was therefore always null,
/// `ThreatPipeline` returned early, and the camera signal could never run on
/// any platform. Everything worked except the one screen that lets someone
/// type in an address.
///
/// ## Why it tests before it saves
///
/// A saved address that answers nothing is worse than no address: the app
/// would show a paired pair of glasses and report the weapon signal as
/// available while no frame ever arrived. So pairing means `GET /status`
/// returned, and nothing else counts.
///
/// Copied from [GlassesPairing].
@ProviderFor(GlassesPairing)
final glassesPairingProvider =
    NotifierProvider<GlassesPairing, GlassesPairingState>.internal(
      GlassesPairing.new,
      name: r'glassesPairingProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$glassesPairingHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GlassesPairing = Notifier<GlassesPairingState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
