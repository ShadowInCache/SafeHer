import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../models/threat_update.dart';
import '../models/emergency_alert.dart';
import '../models/evidence_data.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

class ApiService {
  final http.Client _client = http.Client();

  // Helper to handle response
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body);
    } else {
      throw Exception('API Error: ${response.statusCode} - ${response.body}');
    }
  }

  // Health Check
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl.replaceAll('/api/v1', '')}/health'),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Health check failed: $e');
    }
  }

  // Motion Detection
  Future<Map<String, dynamic>> sendMotionData(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.motionDetectionEndpoint}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Motion detection API failed: $e');
    }
  }

  // Weapon Detection
  Future<Map<String, dynamic>> sendWeaponData(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.weaponDetectionEndpoint}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Weapon detection API failed: $e');
    }
  }

  // Voice Detection
  Future<Map<String, dynamic>> sendVoiceData(Map<String, dynamic> data) async {
    try {
      final response = await _client.post(
        Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.voiceDetectionEndpoint}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Voice detection API failed: $e');
    }
  }

  // Incidents
  Future<Map<String, dynamic>> createIncident(
    Map<String, dynamic> incidentData,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}${AppConstants.incidentsEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(incidentData),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Create incident API failed: $e');
    }
  }

  Future<List<dynamic>> getUserIncidents(String userId) async {
    try {
      final response = await _client.get(
        Uri.parse(
          '${AppConstants.baseUrl}${AppConstants.incidentsEndpoint}/$userId',
        ),
      );
      final data = _handleResponse(response);
      return data['incidents'] ?? [];
    } catch (e) {
      throw Exception('Get incidents API failed: $e');
    }
  }

  // === NEW HYBRID ARCHITECTURE METHODS ===

  /// Get system health status from all microservices
  Future<Map<String, dynamic>> getSystemHealthStatus() async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/system/health'),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('System health check failed: $e');
    }
  }

  /// Trigger manual emergency alert
  Future<Map<String, dynamic>> triggerEmergencyAlert({
    required String userId,
    required Map<String, dynamic> location,
    String? additionalInfo,
    List<String>? evidenceFiles,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/alerts/emergency'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'location': location,
          'additional_info': additionalInfo,
          'evidence_files': evidenceFiles ?? [],
          'source': 'mobile_app_manual',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Emergency alert trigger failed: $e');
    }
  }

  /// Get user's emergency alerts
  Future<List<EmergencyAlert>> getUserEmergencyAlerts(String userId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/alerts/user/$userId'),
      );
      final data = _handleResponse(response);

      final List<dynamic> alertsJson = data['alerts'] ?? [];
      return alertsJson.map((json) => EmergencyAlert.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Get emergency alerts failed: $e');
    }
  }

  /// Acknowledge an emergency alert
  Future<Map<String, dynamic>> acknowledgeEmergencyAlert(String alertId) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/alerts/$alertId/acknowledge'),
        headers: {'Content-Type': 'application/json'},
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Acknowledge alert failed: $e');
    }
  }

  /// Get threat updates for a user
  Future<List<ThreatUpdate>> getUserThreatUpdates(
    String userId, {
    int limit = 10,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/threats/user/$userId?limit=$limit'),
      );
      final data = _handleResponse(response);

      final List<dynamic> threatsJson = data['threats'] ?? [];
      return threatsJson.map((json) => ThreatUpdate.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Get threat updates failed: $e');
    }
  }

  /// Get evidence data for a user
  Future<List<EvidenceData>> getUserEvidence(
    String userId, {
    int limit = 20,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/evidence/user/$userId?limit=$limit'),
      );
      final data = _handleResponse(response);

      final List<dynamic> evidenceJson = data['evidence'] ?? [];
      return evidenceJson.map((json) => EvidenceData.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Get evidence data failed: $e');
    }
  }

  /// Get evidence data for a specific emergency
  Future<List<EvidenceData>> getEmergencyEvidence(String emergencyId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/evidence/emergency/$emergencyId'),
      );
      final data = _handleResponse(response);

      final List<dynamic> evidenceJson = data['evidence'] ?? [];
      return evidenceJson.map((json) => EvidenceData.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Get emergency evidence failed: $e');
    }
  }

  /// Upload evidence file (photo, video, audio)
  Future<Map<String, dynamic>> uploadEvidenceFile({
    required String userId,
    required Uint8List fileBytes,
    required String fileName,
    required String evidenceType,
    String? emergencyId,
    Map<String, dynamic>? location,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConstants.baseUrl}/evidence/upload'),
      );

      // Add form fields
      request.fields['user_id'] = userId;
      request.fields['evidence_type'] = evidenceType;
      request.fields['timestamp'] = DateTime.now().toIso8601String();

      if (emergencyId != null) request.fields['emergency_id'] = emergencyId;
      if (location != null) request.fields['location'] = json.encode(location);
      if (metadata != null) request.fields['metadata'] = json.encode(metadata);

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Evidence upload failed: $e');
    }
  }

  /// Download evidence file (returns encrypted file URL)
  Future<String> getEvidenceFileUrl(String evidenceId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/evidence/$evidenceId/download'),
      );
      final data = _handleResponse(response);
      return data['download_url'] ?? '';
    } catch (e) {
      throw Exception('Get evidence URL failed: $e');
    }
  }

  /// Update user location
  Future<Map<String, dynamic>> updateUserLocation({
    required String userId,
    required Map<String, dynamic> location,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/users/$userId/location'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'location': location,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Update location failed: $e');
    }
  }

  /// Get connected devices for a user
  Future<List<dynamic>> getUserDevices(String userId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/devices/user/$userId'),
      );
      final data = _handleResponse(response);
      return data['devices'] ?? [];
    } catch (e) {
      throw Exception('Get user devices failed: $e');
    }
  }

  /// Register a new device (ESP32 glove/glasses)
  Future<Map<String, dynamic>> registerDevice({
    required String userId,
    required String deviceType,
    required String deviceId,
    Map<String, dynamic>? deviceInfo,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/devices/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'device_type': deviceType,
          'device_id': deviceId,
          'device_info': deviceInfo ?? {},
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Device registration failed: $e');
    }
  }

  /// Get microservice status
  Future<Map<String, dynamic>> getMicroserviceStatus() async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/system/services'),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Get microservice status failed: $e');
    }
  }

  /// Send sensor data directly (alternative to MQTT/WebSocket)
  Future<Map<String, dynamic>> sendSensorData({
    required String userId,
    required String deviceType,
    required Map<String, dynamic> sensorData,
    required Map<String, dynamic> location,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/sensors/data'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'device_type': deviceType,
          'sensor_data': sensorData,
          'location': location,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Send sensor data failed: $e');
    }
  }

  /// Get user's emergency contacts
  // Emergency Contacts Management

  Future<List<dynamic>> getUserEmergencyContacts(String userId) async {
    try {
      final response = await _client.get(
        Uri.parse('${AppConstants.baseUrl}/emergency-contacts/$userId'),
      );
      final data = _handleResponse(response);
      return data['contacts'] ?? [];
    } catch (e) {
      throw Exception('Get emergency contacts failed: $e');
    }
  }

  /// Add a new emergency contact
  Future<Map<String, dynamic>> addEmergencyContact({
    required String userId,
    required String name,
    required String phoneNumber,
    String? email,
    String relationship = 'friend',
    int priority = 1,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/emergency-contacts'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': userId,
          'name': name,
          'phone_number': phoneNumber,
          'email': email,
          'relationship': relationship,
          'priority': priority,
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Add emergency contact failed: $e');
    }
  }

  /// Update an emergency contact
  Future<Map<String, dynamic>> updateEmergencyContact({
    required String contactId,
    String? name,
    String? phoneNumber,
    String? email,
    String? relationship,
    int? priority,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (phoneNumber != null) body['phone_number'] = phoneNumber;
      if (email != null) body['email'] = email;
      if (relationship != null) body['relationship'] = relationship;
      if (priority != null) body['priority'] = priority;

      final response = await _client.put(
        Uri.parse('${AppConstants.baseUrl}/emergency-contacts/$contactId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Update emergency contact failed: $e');
    }
  }

  /// Delete an emergency contact
  Future<Map<String, dynamic>> deleteEmergencyContact(String contactId) async {
    try {
      final response = await _client.delete(
        Uri.parse('${AppConstants.baseUrl}/emergency-contacts/$contactId'),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Delete emergency contact failed: $e');
    }
  }

  /// Update user's emergency contacts (legacy method - kept for compatibility)
  Future<Map<String, dynamic>> updateEmergencyContacts({
    required String userId,
    required List<Map<String, dynamic>> contacts,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConstants.baseUrl}/users/$userId/emergency-contacts'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contacts': contacts,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Update emergency contacts failed: $e');
    }
  }
}
