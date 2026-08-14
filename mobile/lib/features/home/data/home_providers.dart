import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/home_repository.dart';
import '../domain/models/home_summary.dart';
import 'home_repository_mock.dart';
import 'home_repository_remote.dart';

part 'home_providers.g.dart';

@riverpod
HomeRepository homeRepository(Ref ref) {
  if (AppConfig.useMockApi) return HomeRepositoryMock();
  return HomeRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
Future<HomeSummary> homeSummary(Ref ref) async {
  return ref.watch(homeRepositoryProvider).getHomeSummary();
}
