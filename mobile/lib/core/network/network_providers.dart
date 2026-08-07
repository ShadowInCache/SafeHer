import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'api_client.dart';
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
