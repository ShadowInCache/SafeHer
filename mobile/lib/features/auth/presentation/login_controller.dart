import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../safety/data/safety_providers.dart';
import '../data/auth_providers.dart';

part 'login_controller.g.dart';

@riverpod
class LoginController extends _$LoginController {
  @override
  FutureOr<void> build() {}

  Future<void> signIn({required String email, required String password}) async {
    await _run(() => ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password));
  }

  Future<void> signInAsGuest() async {
    await _run(() => ref.read(authRepositoryProvider).signInAsGuest());
  }

  Future<void> signInWithGoogle() async {
    await _run(() => ref.read(authRepositoryProvider).signInWithGoogle());
  }

  Future<void> signInWithApple() async {
    await _run(() => ref.read(authRepositoryProvider).signInWithApple());
  }

  Future<void> _run(Future<void> Function() signIn) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(signIn);
    // Session-scoped state loaded before sign-in holds unauthenticated
    // defaults; reload it now that a real session exists.
    if (!state.hasError) {
      ref.read(safetyPreferencesNotifierProvider.notifier).refreshAfterSignIn();
    }
  }
}
