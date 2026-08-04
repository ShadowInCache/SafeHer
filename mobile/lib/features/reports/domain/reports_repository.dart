import 'models/report_detail.dart';
import 'models/report_summary.dart';

abstract class ReportsRepository {
  Future<List<ReportSummary>> getReports();
  Future<ReportDetail> getReportDetail(String id);
}
