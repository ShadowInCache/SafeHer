import 'package:flutter_riverpod/flutter_riverpod.dart';

const String currentUserId = 'user_001';

// Mock alerts - standalone mode (no backend calls)
final alertsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  await Future.delayed(const Duration(milliseconds: 500));
  return [
    {
      'id': 'alert_001',
      'type': 'Motion Detected',
      'severity': 'medium',
      'timestamp': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toIso8601String(),
      'location': 'Front Door',
    },
    {
      'id': 'alert_002',
      'type': 'Loud Voice Detected',
      'severity': 'high',
      'timestamp': DateTime.now()
          .subtract(const Duration(minutes: 15))
          .toIso8601String(),
      'location': 'Living Room',
    },
  ];
});

// Mock recent events - standalone mode (no backend calls)
final recentEventsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  await Future.delayed(const Duration(milliseconds: 500));
  return [
    {
      'id': 'event_001',
      'type': 'Device Connected',
      'timestamp': DateTime.now()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'status': 'success',
    },
    {
      'id': 'event_002',
      'type': 'Location Updated',
      'timestamp': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toIso8601String(),
      'status': 'success',
    },
  ];
});

final threatLevelProvider = StateProvider<int>((ref) => 12);
final incidentCountProvider = StateProvider<int>((ref) => 0);
