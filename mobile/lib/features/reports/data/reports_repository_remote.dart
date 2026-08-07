import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/components/charts/sa_motion_chart.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/models/report_detail.dart';
import '../domain/models/report_summary.dart';
import '../domain/reports_repository.dart';

/// Firestore-backed [ReportsRepository]. Reports live at
/// `users/{uid}/reports/{reportId}`, written by the same backend pipeline
/// that generates an incident from the live monitoring stream — this only
/// reads them.
class ReportsRepositoryRemote implements ReportsRepository {
  ReportsRepositoryRemote({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return _firestore.collection('users').doc(uid).collection('reports');
  }

  ThreatLevel _levelFromName(String? name) =>
      ThreatLevel.values.firstWhere((l) => l.name == name, orElse: () => ThreatLevel.safe);

  ReportSummary _summaryFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ReportSummary(
      id: doc.id,
      date: data['date'] as String? ?? '',
      type: data['type'] as String? ?? 'Incident',
      level: _levelFromName(data['level'] as String?),
      summarySnippet: data['summarySnippet'] as String? ?? '',
    );
  }

  @override
  Future<List<ReportSummary>> getReports() async {
    final snapshot = await _collection.orderBy('date', descending: true).get();
    return snapshot.docs.map(_summaryFromDoc).toList();
  }

  @override
  Future<ReportDetail> getReportDetail(String id) async {
    final doc = await _collection.doc(id).get();
    final data = doc.data();
    if (data == null) throw StateError('Report $id not found.');

    final waveform = (data['waveform'] as List<dynamic>? ?? const []).map((v) => (v as num).toDouble()).toList();
    final motionSamples = (data['motionSamples'] as List<dynamic>? ?? const [])
        .map(
          (raw) => MotionSample(
            x: ((raw as Map<String, dynamic>)['x'] as num).toDouble(),
            y: (raw['y'] as num).toDouble(),
            z: (raw['z'] as num).toDouble(),
          ),
        )
        .toList();
    final motionEvents = (data['motionEvents'] as List<dynamic>? ?? const [])
        .map(
          (raw) => MotionEventPin(
            sampleIndex: (raw as Map<String, dynamic>)['sampleIndex'] as int,
            label: raw['label'] as String,
            timestamp: raw['timestamp'] as String,
          ),
        )
        .toList();

    return ReportDetail(
      id: doc.id,
      date: data['date'] as String? ?? '',
      time: data['time'] as String? ?? '',
      type: data['type'] as String? ?? 'Incident',
      level: _levelFromName(data['level'] as String?),
      fullSummary: data['fullSummary'] as String? ?? '',
      locationLabel: data['locationLabel'] as String? ?? 'Unknown location',
      waveform: waveform,
      motionSamples: motionSamples,
      motionEvents: motionEvents,
    );
  }
}
