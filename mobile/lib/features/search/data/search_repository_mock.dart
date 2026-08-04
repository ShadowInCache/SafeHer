import '../../../shared/models/threat_level.dart';
import '../domain/models/search_result.dart';
import '../domain/search_repository.dart';

class SearchRepositoryMock implements SearchRepository {
  @override
  Future<SearchIndex> getSearchIndex() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return const SearchIndex(
      incidents: [
        SearchIncidentResult(
          id: '1',
          date: 'Aug 2',
          type: 'Elevated motion detected',
          level: ThreatLevel.elevated,
          summarySnippet: 'Sudden acceleration spike near Elm Street.',
        ),
        SearchIncidentResult(
          id: '2',
          date: 'Aug 1',
          type: 'Routine check-in',
          level: ThreatLevel.safe,
          summarySnippet: 'All monitored signals within normal range.',
        ),
        SearchIncidentResult(
          id: '3',
          date: 'Jul 30',
          type: 'Loud noise detected',
          level: ThreatLevel.caution,
          summarySnippet: 'Brief audio spike while walking home.',
        ),
      ],
      contacts: [
        SearchContactResult(id: '1', name: 'Anika Sharma', relationship: 'Sister', priority: 1),
        SearchContactResult(id: '2', name: 'Rahul Verma', relationship: 'Partner', priority: 2),
        SearchContactResult(id: '3', name: 'Meera Iyer', relationship: 'Friend', priority: 3, confirmed: false),
      ],
      devices: [
        SearchDeviceResult(id: 'ring', name: 'Smart Ring', batteryPercent: 0.82, signalStrength: 3, isOnline: true),
        SearchDeviceResult(id: 'glasses', name: 'Safety Glasses', batteryPercent: 0.46, signalStrength: 2, isOnline: true),
        SearchDeviceResult(id: 'pendant', name: 'Pendant', batteryPercent: 0.09, signalStrength: 1, isOnline: false),
      ],
    );
  }
}
