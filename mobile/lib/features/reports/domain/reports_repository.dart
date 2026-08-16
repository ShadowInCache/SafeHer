import 'dart:typed_data';

import 'models/report_detail.dart';
import 'models/report_summary.dart';

abstract class ReportsRepository {
  Future<List<ReportSummary>> getReports();
  Future<ReportDetail> getReportDetail(String id);

  /// The forensic PDF for one incident (SRS FR-RPT-03), as bytes.
  ///
  /// Bytes rather than a URL: the endpoint is authenticated, so a plain
  /// link would 401 in any external viewer.
  Future<Uint8List> exportPdf(String incidentId);

  /// Mints a time-limited read-only link to the incident (FR-RPT-06) and
  /// returns the URL to hand out.
  Future<String> createShareLink(String incidentId);
}
