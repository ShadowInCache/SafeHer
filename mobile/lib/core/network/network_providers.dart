import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'api_client.dart';
import 'backend_warmer.dart';
import 'auth_token_store.dart';

part 'network_providers.g.dart';

@Riverpod(keepAlive: true)
AuthTokenStore authTokenStore(Ref ref) {
  return AuthTokenStore();
}

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) {
  return ApiClient(tokenStore: ref.watch(authTokenStoreProvider));
}

/// Wakes a suspended backend before an emergency dispatch. See
/// [BackendWarmer] for why the SOS countdown is the right moment.
@riverpod
BackendWarmer backendWarmer(Ref ref) =>
    BackendWarmerRemote(apiClient: ref.watch(apiClientProvider));
