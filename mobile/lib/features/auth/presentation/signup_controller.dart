import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../safety/data/safety_providers.dart';
import '../data/auth_providers.dart';

part 'signup_controller.g.dart';

@riverpod
class SignupController extends _$SignupController {
  @override
  FutureOr<void> build() {}

  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneE164,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUp(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phoneE164: phoneE164,
        password: password,
      ),
    );
    if (!state.hasError) {
      ref.read(safetyPreferencesNotifierProvider.notifier).refreshAfterSignIn();
    }
  }
}
