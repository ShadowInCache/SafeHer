import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/auth_providers.dart';

part 'otp_controller.g.dart';

@riverpod
class OtpController extends _$OtpController {
  @override
  FutureOr<void> build() {}

  Future<void> verify(String code) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).verifyOtp(code));
  }

  Future<void> resend() async {
    await ref.read(authRepositoryProvider).resendOtp();
  }
}
