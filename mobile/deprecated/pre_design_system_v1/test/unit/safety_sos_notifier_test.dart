import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/shared/state/safety_sos_notifier.dart';

void main() {
  test('start sets pending state and countdown', () {
    final notifier = SafetySosNotifier();

    notifier.start(auto: true, onDispatch: () async {});

    expect(notifier.state.sosPending, isTrue);
    expect(notifier.state.sosCountdown, 5);
    expect(notifier.state.liveLocationSharing, isTrue);

    notifier.dispose();
  });

  test('cancel clears pending state', () {
    final notifier = SafetySosNotifier();

    notifier.start(auto: false, onDispatch: () async {});
    notifier.cancel();

    expect(notifier.state.sosPending, isFalse);
    expect(notifier.state.sosCountdown, 0);
    expect(notifier.state.liveLocationSharing, isFalse);
  });

  test('completeDispatch keeps sharing enabled and clears countdown', () {
    final notifier = SafetySosNotifier();

    notifier.start(auto: true, onDispatch: () async {});
    notifier.completeDispatch();

    expect(notifier.state.sosPending, isFalse);
    expect(notifier.state.sosCountdown, 0);
    expect(notifier.state.liveLocationSharing, isTrue);
  });
}
