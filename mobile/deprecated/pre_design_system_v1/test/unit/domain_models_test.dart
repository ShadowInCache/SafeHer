import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/shared/models/domain_models.dart';

void main() {
  group('AppUser', () {
    test('fromJson maps role and fallback values', () {
      final user = AppUser.fromJson({
        'user_id': 'u-100',
        'name': 'Asha Rao',
        'email': 'asha@safeher.app',
        'role': 'guardian',
      });

      expect(user.id, 'u-100');
      expect(user.fullName, 'Asha Rao');
      expect(user.email, 'asha@safeher.app');
      expect(user.role, AppRole.guardian);
    });
  });

  group('IncidentRecord', () {
    test('toJson and fromJson preserve key values', () {
      final incident = IncidentRecord(
        id: 'inc-1',
        createdAt: DateTime.parse('2026-01-01T10:15:30.000Z'),
        severity: ThreatLevelState.warning,
        summary: 'Potential risk pattern observed',
        location: GeoCoordinate(
          latitude: 12.98,
          longitude: 77.60,
          timestamp: DateTime.parse('2026-01-01T10:15:30.000Z'),
        ),
        evidenceFiles: const ['a.enc'],
        synced: true,
      );

      final copy = IncidentRecord.fromJson(incident.toJson());

      expect(copy.id, incident.id);
      expect(copy.severity, incident.severity);
      expect(copy.summary, incident.summary);
      expect(copy.location.latitude, incident.location.latitude);
      expect(copy.location.longitude, incident.location.longitude);
      expect(copy.synced, isTrue);
    });
  });
}
