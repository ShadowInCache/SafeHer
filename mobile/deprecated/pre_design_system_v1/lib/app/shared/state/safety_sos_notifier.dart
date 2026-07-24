import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class SafetySosState {
  final bool sosPending;
  final int sosCountdown;
  final bool liveLocationSharing;

  const SafetySosState({
    required this.sosPending,
    required this.sosCountdown,
    required this.liveLocationSharing,
  });

  factory SafetySosState.initial() {
    return const SafetySosState(
      sosPending: false,
      sosCountdown: 0,
      liveLocationSharing: false,
    );
  }

  SafetySosState copyWith({
    bool? sosPending,
    int? sosCountdown,
    bool? liveLocationSharing,
  }) {
    return SafetySosState(
      sosPending: sosPending ?? this.sosPending,
      sosCountdown: sosCountdown ?? this.sosCountdown,
      liveLocationSharing: liveLocationSharing ?? this.liveLocationSharing,
    );
  }
}

class SafetySosNotifier extends StateNotifier<SafetySosState> {
  Timer? _timer;

  SafetySosNotifier() : super(SafetySosState.initial());

  bool get isPending => state.sosPending;

  void start({
    required bool auto,
    required Future<void> Function() onDispatch,
  }) {
    if (state.sosPending) {
      return;
    }

    state = state.copyWith(
      sosPending: true,
      sosCountdown: auto ? 5 : 8,
      liveLocationSharing: true,
    );

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final next = state.sosCountdown - 1;
      if (next <= 0) {
        timer.cancel();
        await onDispatch();
      } else {
        state = state.copyWith(sosCountdown: next);
      }
    });
  }

  void completeDispatch() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(
      sosPending: false,
      sosCountdown: 0,
      liveLocationSharing: true,
    );
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = state.copyWith(
      sosPending: false,
      sosCountdown: 0,
      liveLocationSharing: false,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
