import '../../../../shared/models/threat_level.dart';

enum SearchCategory { all, incidents, contacts, devices }

class SearchIncidentResult {
  const SearchIncidentResult({
    required this.id,
    required this.date,
    required this.type,
    required this.level,
    required this.summarySnippet,
  });

  final String id;
  final String date;
  final String type;
  final ThreatLevel level;
  final String summarySnippet;
}

class SearchContactResult {
  const SearchContactResult({
    required this.id,
    required this.name,
    required this.relationship,
    required this.priority,
    this.confirmed = true,
  });

  final String id;
  final String name;
  final String relationship;
  final int priority;
  final bool confirmed;
}

class SearchDeviceResult {
  const SearchDeviceResult({
    required this.id,
    required this.name,
    required this.batteryPercent,
    required this.signalStrength,
    required this.isOnline,
  });

  final String id;
  final String name;
  final double batteryPercent;
  final int signalStrength;
  final bool isOnline;
}

/// The full searchable dataset. The Search screen filters this client-side
/// as the user types — the real (Phase 4) implementation will replace this
/// with a server-side query, but the shape callers see stays the same.
class SearchIndex {
  const SearchIndex({required this.incidents, required this.contacts, required this.devices});

  final List<SearchIncidentResult> incidents;
  final List<SearchContactResult> contacts;
  final List<SearchDeviceResult> devices;
}
