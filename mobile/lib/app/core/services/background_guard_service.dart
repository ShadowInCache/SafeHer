import 'dart:async';

class BackgroundGuardService {
  Timer? _timer;
  bool _running = false;

  bool get isRunning => _running;

  void start({
    required Future<void> Function() onTick,
    Duration interval = const Duration(seconds: 25),
  }) {
    stop();
    _running = true;

    _timer = Timer.periodic(interval, (_) async {
      await onTick();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }
}
