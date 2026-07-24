import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/auth_repository.dart';
import 'auth_repository_mock.dart';

part 'auth_providers.g.dart';

/// Switches between the mock and (eventually) Firebase-backed
/// [AuthRepository] based on [AppFlavor.isMock].
@riverpod
AuthRepository authRepository(Ref ref) {
  return AuthRepositoryMock();
}
