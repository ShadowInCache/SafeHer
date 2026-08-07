import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../domain/auth_repository.dart';
import 'auth_repository_mock.dart';
import 'auth_repository_remote.dart';

part 'auth_providers.g.dart';

/// Switches between the mock and Firebase-backed [AuthRepository] based on
/// [AppConfig.useMockApi].
@riverpod
AuthRepository authRepository(Ref ref) {
  if (AppConfig.useMockApi) return AuthRepositoryMock();
  return AuthRepositoryRemote();
}
