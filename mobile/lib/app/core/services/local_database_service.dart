import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../shared/models/domain_models.dart';

class LocalDatabaseService {
  Database? _db;
  bool _memoryMode = false;
  final Map<String, IncidentRecord> _incidentCache = <String, IncidentRecord>{};
  final Map<String, EmergencyContactModel> _contactCache =
      <String, EmergencyContactModel>{};
  final Map<String, NotificationRecordModel> _notificationCache =
      <String, NotificationRecordModel>{};
  final Map<String, String> _settingsCache = <String, String>{};

  Future<void> initialize() async {
    if (_db != null || _memoryMode) {
      return;
    }

    if (kIsWeb) {
      _enableMemoryMode();
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(dir.path, 'safeher_offline.db');
      _db = await openDatabase(dbPath, version: 1, onCreate: _onCreate);
    } on MissingPluginException {
      _enableMemoryMode();
    } on UnsupportedError {
      _enableMemoryMode();
    } on DatabaseException {
      _enableMemoryMode();
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE incidents(
        id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL,
        severity TEXT NOT NULL,
        summary TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE emergency_contacts(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        email TEXT,
        relationship TEXT NOT NULL,
        priority INTEGER NOT NULL,
        is_guardian INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE notifications(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        severity TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Database get _database {
    final database = _db;
    if (database == null) {
      throw StateError('LocalDatabaseService not initialized');
    }
    return database;
  }

  Future<void> upsertIncident(IncidentRecord incident) async {
    if (_memoryMode) {
      _incidentCache[incident.id] = incident;
      return;
    }

    await _database.insert(
      'incidents',
      incident.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<IncidentRecord>> loadIncidents({int limit = 50}) async {
    if (_memoryMode) {
      final records = _incidentCache.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (records.length <= limit) {
        return records;
      }
      return records.sublist(0, limit);
    }

    final rows = await _database.query(
      'incidents',
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return rows.map((row) => IncidentRecord.fromJson(row)).toList();
  }

  Future<void> upsertContact(EmergencyContactModel contact) async {
    if (_memoryMode) {
      _contactCache[contact.id] = contact;
      return;
    }

    await _database.insert('emergency_contacts', {
      'id': contact.id,
      'name': contact.name,
      'phone': contact.phone,
      'email': contact.email,
      'relationship': contact.relationship,
      'priority': contact.priority,
      'is_guardian': contact.isGuardian ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteContact(String contactId) async {
    if (_memoryMode) {
      _contactCache.remove(contactId);
      return;
    }

    await _database.delete(
      'emergency_contacts',
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }

  Future<List<EmergencyContactModel>> loadContacts() async {
    if (_memoryMode) {
      final contacts = _contactCache.values.toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      return contacts;
    }

    final rows = await _database.query(
      'emergency_contacts',
      orderBy: 'priority ASC',
    );

    return rows
        .map(
          (row) => EmergencyContactModel(
            id: row['id'].toString(),
            name: row['name'].toString(),
            phone: row['phone'].toString(),
            email: row['email']?.toString(),
            relationship: row['relationship'].toString(),
            priority: (row['priority'] as int?) ?? 5,
            isGuardian: (row['is_guardian'] as int? ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<void> upsertNotification(NotificationRecordModel item) async {
    if (_memoryMode) {
      _notificationCache[item.id] = item;
      return;
    }

    await _database.insert('notifications', {
      'id': item.id,
      'title': item.title,
      'body': item.body,
      'severity': item.severity.name,
      'created_at': item.time.toIso8601String(),
      'is_read': item.read ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<NotificationRecordModel>> loadNotifications({
    int limit = 100,
  }) async {
    if (_memoryMode) {
      final notifications = _notificationCache.values.toList()
        ..sort((a, b) => b.time.compareTo(a.time));
      if (notifications.length <= limit) {
        return notifications;
      }
      return notifications.sublist(0, limit);
    }

    final rows = await _database.query(
      'notifications',
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return rows
        .map(
          (row) => NotificationRecordModel(
            id: row['id'].toString(),
            title: row['title'].toString(),
            body: row['body'].toString(),
            time:
                DateTime.tryParse(row['created_at'].toString()) ??
                DateTime.now(),
            severity: _severityFromString(row['severity'].toString()),
            read: (row['is_read'] as int? ?? 0) == 1,
          ),
        )
        .toList();
  }

  Future<void> setSetting(String key, String value) async {
    if (_memoryMode) {
      _settingsCache[key] = value;
      return;
    }

    await _database.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    if (_memoryMode) {
      return _settingsCache[key];
    }

    final rows = await _database.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first['value']?.toString();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _memoryMode = false;
    _incidentCache.clear();
    _contactCache.clear();
    _notificationCache.clear();
    _settingsCache.clear();
  }

  void _enableMemoryMode() {
    _memoryMode = true;
    _db = null;
  }

  ThreatLevelState _severityFromString(String severity) {
    switch (severity.toLowerCase()) {
      case 'danger':
      case 'critical':
      case 'high':
        return ThreatLevelState.danger;
      case 'warning':
      case 'medium':
        return ThreatLevelState.warning;
      default:
        return ThreatLevelState.safe;
    }
  }
}
