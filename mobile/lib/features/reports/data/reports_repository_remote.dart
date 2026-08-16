import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/threat_level.dart';
import '../../../core/network/api_client.dart';
import '../domain/models/report_detail.dart';
import '../domain/models/report_summary.dart';
import '../domain/reports_repository.dart';

/// `fastapi_app`-backed [ReportsRepository] — `GET /api/v1/incidents` and
/// `GET /api/v1/incidents/{id}`.
///
/// The backend's `Incident` record is far simpler than [ReportDetail]'s
/// full shape: no event timeline, no evidence gallery, no chain-of-custody
/// hash, and GPS is only present when the incident was actually created
/// with a location fix (see `fastapi_app/routers/alerts.py`). Every one of
/// those stays empty/null here rather than being invented —
/// `report_detail_screen.dart` already hides each of those sections
/// entirely when its data is empty, so this renders as an honestly sparser
/// screen rather than a broken one.
class ReportsRepositoryRemote implements ReportsRepository {
  ReportsRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  ThreatLevel _levelFromBackend(String? threatLevel) => switch (threatLevel?.toLowerCase()) {
    'critical' => ThreatLevel.danger,
    'high' => ThreatLevel.elevated,
    'medium' => ThreatLevel.caution,
    'low' => ThreatLevel.safe,
    _ => ThreatLevel.safe,
  };

  ReportSummary _summaryFromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now();
    return ReportSummary(
      id: json['id'] as String,
      date: _formatDate(createdAt),
      type: json['title'] as String? ?? 'Incident',
      level: _levelFromBackend(json['threat_level'] as String?),
      summarySnippet: (json['description'] as String?) ?? 'No summary available.',
    );
  }

  @override
  Future<List<ReportSummary>> getReports() async {
    final response = await _apiClient.dio.get('/incidents/');
    return (response.data as List).cast<Map<String, dynamic>>().map(_summaryFromJson).toList();
  }

  @override
  Future<Uint8List> exportPdf(String incidentId) async {
    final response = await _apiClient.dio.get<List<int>>(
      '/incidents/$incidentId/report.pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  @override
  Future<String> createShareLink(String incidentId) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/incidents/$incidentId/share',
    );
    final token = response.data?['token'] as String?;
    if (token == null) {
      throw const ApiException(message: 'The server returned no link. Please try again.');
    }
    // Built from the API base so the link points at the same deployment the
    // app is talking to, rather than a hardcoded host that would be wrong
    // on every environment but one.
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/share/$token';
  }

  @override
  Future<ReportDetail> getReportDetail(String id) async {
    final response = await _apiClient.dio.get('/incidents/$id');
    final json = response.data as Map<String, dynamic>;
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now();
    final latitude = (json['latitude'] as num?)?.toDouble();
    final longitude = (json['longitude'] as num?)?.toDouble();

    return ReportDetail(
      id: json['id'] as String,
      date: _formatDate(createdAt),
      time: _formatTime(createdAt),
      type: json['title'] as String? ?? 'Incident',
      level: _levelFromBackend(json['threat_level'] as String?),
      fullSummary: (json['description'] as String?) ?? 'No summary available.',
      locationLabel: latitude != null && longitude != null
          ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
          : 'Location unavailable',
      // No REST endpoint returns live sensor waveforms/motion samples for a
      // past incident — that's the live-monitoring WebSocket feed's domain,
      // not incident history.
      waveform: const [],
      motionSamples: const [],
      motionEvents: const [],
      timeline: const [],
      evidence: const [],
      gpsBreadcrumbs: const [],
      chainOfCustodyHash: null,
    );
  }

  String _formatDate(DateTime dt) => '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
