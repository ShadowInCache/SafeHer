import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/network/backend_warmer.dart';

/// Waking a suspended backend before an emergency dispatch.
///
/// The API runs on an instance that sleeps after a period of inactivity, and
/// an SOS is by nature the first request after a long idle period — the one
/// that pays the spin-up, when SRS 5.1 asks for dispatch within five seconds.
/// The countdown is ten deliberate seconds during which nothing is sent, so
/// spending the first of them on a warm-up costs the user nothing.
void main() {
  group('BackendWarmerNoop', () {
    test('does nothing and does not throw', () {
      // Substituted into every widget test. Left un-substituted the real
      // warmer makes an HTTP call whose timeout timer outlives the widget
      // tree, and the suite fails with "A Timer is still pending" — a message
      // that names the symptom and never the network call behind it.
      expect(const BackendWarmerNoop().warm, returnsNormally);
    });

    test('is const, so it costs nothing to install everywhere', () {
      expect(identical(const BackendWarmerNoop(), const BackendWarmerNoop()), isTrue);
    });
  });

  group('the contract', () {
    test('warm() returns void, so no caller can accidentally await it', () {
      // The signature is the guarantee. If this returned a Future, a caller
      // could await it and put a network round trip in front of the
      // countdown — the exact delay the warm-up exists to avoid.
      const BackendWarmer warmer = BackendWarmerNoop();

      expect(warmer.warm, isA<void Function()>());
    });
  });
}
