import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/dashboard_repository.dart';
import '../domain/models/dashboard_summary.dart';
import 'dashboard_repository_mock.dart';
import 'dashboard_repository_remote.dart';

part 'dashboard_providers.g.dart';

@riverpod
DashboardRepository dashboardRepository(Ref ref) {
  if (AppConfig.useMockApi) return DashboardRepositoryMock();
  return DashboardRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
Future<DashboardSummary> dashboardSummary(Ref ref) async {
  return ref.watch(dashboardRepositoryProvider).getDashboardSummary();
}
