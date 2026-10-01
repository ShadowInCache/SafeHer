import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'api_client.dart';

/// Wakes a sleeping backend ahead of a request that must not wait.
///
/// The API is hosted on an instance that suspends after a period of
/// inactivity. An SOS is by its nature the first request after a long idle
/// period — precisely the one that pays the several-second spin-up, when SRS
/// section 5.1 asks for dispatch within five seconds.
///
/// The emergency countdown is a free window to spend on this: the user has
/// ten deliberate seconds before anything is sent, so a cheap request fired
/// at the start of it means the server is already awake when the alert
/// follows.
///
/// An interface rather than a bare function so widget tests can substitute a
/// no-op. Left un-substituted it is a real HTTP call whose timeout timer
/// outlives the widget tree, and the test fails with "A Timer is still
/// pending" — a message that names the symptom and never the network call
/// behind it.
abstract class BackendWarmer {
  /// Fire-and-forget. Never throws, never awaited by the caller: this is a
  /// warm-up, and the request that follows reports its own outcome.
  void warm();
}

class BackendWarmerRemote implements BackendWarmer {
  BackendWarmerRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  void warm() => unawaited(_warm());

  Future<void> _warm() async {
    try {
      // The default receive timeout is 15 seconds and a cold start takes about
      // 60, so this request would otherwise give up long before the thing it
      // asked for had happened. Sending it still *triggers* the wake — the
      // instance starts on the inbound connection — but giving up early means
      // never learning whether it worked, and never logging that it did not.
      await _apiClient.dio.get(
        '/health',
        options: Options(receiveTimeout: AppConfig.apiColdStartReceiveTimeout),
      );
      debugPrint('SafeHer: backend is awake');
    } catch (error) {
      // A failed warm-up costs nothing on its own. The request that follows
      // reports its own outcome, and that is the one the user is waiting on.
      debugPrint('SafeHer: backend warm-up did not complete: $error');
    }
  }
}

/// Does nothing, for tests and for any build with no backend to wake.
class BackendWarmerNoop implements BackendWarmer {
  const BackendWarmerNoop();

  @override
  void warm() {}
}
