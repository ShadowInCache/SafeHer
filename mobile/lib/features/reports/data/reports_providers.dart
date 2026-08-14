import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/models/report_detail.dart';
import '../domain/models/report_summary.dart';
import '../domain/reports_repository.dart';
import 'reports_repository_mock.dart';
import 'reports_repository_remote.dart';

part 'reports_providers.g.dart';

@riverpod
ReportsRepository reportsRepository(Ref ref) {
  if (AppConfig.useMockApi) return ReportsRepositoryMock();
  return ReportsRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
Future<List<ReportSummary>> reportsList(Ref ref) async {
  return ref.watch(reportsRepositoryProvider).getReports();
}

@riverpod
Future<ReportDetail> reportDetail(Ref ref, String id) async {
  return ref.watch(reportsRepositoryProvider).getReportDetail(id);
}
