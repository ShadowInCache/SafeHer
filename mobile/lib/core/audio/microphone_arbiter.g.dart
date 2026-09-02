// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'microphone_arbiter.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$microphoneArbiterHash() => r'554e13a43c256a3ad3535fe164ae48d9787deb7e';

/// Tracks which use currently owns the microphone.
///
/// Deliberately advisory rather than enforcing: it does not wrap the platform
/// APIs, it tells the threat monitor when to get out of the way. Wrapping them
/// would mean routing an emergency recording through a lock, and a lock is one
/// more thing that can fail while someone is being attacked.
///
/// The failure this prevents is real and was live in the shipped code: the
/// emergency screen calls `_startRecording()` on entry while the audio monitor
/// is still listening, and on Android `SpeechRecognizer` and `record` contend
/// for the same hardware. Whichever lost, lost silently.
///
/// Copied from [MicrophoneArbiter].
@ProviderFor(MicrophoneArbiter)
final microphoneArbiterProvider =
    NotifierProvider<MicrophoneArbiter, MicrophoneUse>.internal(
      MicrophoneArbiter.new,
      name: r'microphoneArbiterProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$microphoneArbiterHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$MicrophoneArbiter = Notifier<MicrophoneUse>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
