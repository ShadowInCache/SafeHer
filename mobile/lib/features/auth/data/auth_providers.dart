import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/auth_repository.dart';
import 'auth_repository_mock.dart';
import 'auth_repository_native.dart';
import 'auth_repository_remote.dart';

part 'auth_providers.g.dart';

/// Selects the [AuthRepository] implementation.
///
/// * [AppConfig.useMockApi] -- fixture data, no network.
/// * [AppConfig.useFirebaseAuth] -- Firebase collects the credential and the
///   resulting ID token is exchanged for a backend JWT. Needed for Google and
///   Apple sign-in, and requires Firebase Authentication to be enabled in the
///   console.
/// * Otherwise -- `fastapi_app` serves email/password auth directly, which is
///   the default because it works without any console configuration.
@riverpod
AuthRepository authRepository(Ref ref) {
  if (AppConfig.useMockApi) return AuthRepositoryMock();
  if (AppConfig.useFirebaseAuth) {
    return AuthRepositoryRemote(
      apiClient: ref.watch(apiClientProvider),
      tokenStore: ref.watch(authTokenStoreProvider),
    );
  }
  return AuthRepositoryNative(
    apiClient: ref.watch(apiClientProvider),
    tokenStore: ref.watch(authTokenStoreProvider),
  );
}
