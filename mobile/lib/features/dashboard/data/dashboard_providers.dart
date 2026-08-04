import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/dashboard_repository.dart';
import '../domain/models/dashboard_summary.dart';
import 'dashboard_repository_mock.dart';

part 'dashboard_providers.g.dart';

@riverpod
DashboardRepository dashboardRepository(Ref ref) {
  return DashboardRepositoryMock();
}

@riverpod
Future<DashboardSummary> dashboardSummary(Ref ref) async {
  return ref.watch(dashboardRepositoryProvider).getDashboardSummary();
}
