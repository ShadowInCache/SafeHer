import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/auth_providers.dart';

part 'login_controller.g.dart';

@riverpod
class LoginController extends _$LoginController {
  @override
  FutureOr<void> build() {}

  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password),
    );
  }
}
