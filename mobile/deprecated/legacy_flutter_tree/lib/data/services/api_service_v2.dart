import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/api_constants.dart';
import '../models/user.dart';
import '../models/threat_analysis.dart';
import '../models/evidence_data.dart';
import '../models/chat_room.dart' hide Message;
import '../models/message.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

class ApiService {
  final http.Client _client = http.Client();
  String? _authToken;

  // Authentication headers
  Future<Map<String, String>> _getHeaders({bool requireAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requireAuth && _authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    return headers;
  }

  // Handle API response
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return json.decode(response.body);
    } else {
      final errorBody = response.body.isNotEmpty
          ? json.decode(response.body)
          : {};
      final errorMessage =
          errorBody['detail'] ?? errorBody['message'] ?? 'API Error';
      throw ApiException(
        message: errorMessage,
        statusCode: response.statusCode,
        details: errorBody,
      );
    }
  }

  // Set authentication token
  void setAuthToken(String token) {
    _authToken = token;
  }

  // Clear authentication token
  void clearAuthToken() {
    _authToken = null;
  }

  // =============================================================================
  // AUTHENTICATION & USER MANAGEMENT
  // =============================================================================

  /// Register a new user
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? phoneNumber,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/register'),
        headers: await _getHeaders(requireAuth: false),
        body: json.encode({
          'email': email,
          'password': password,
          'name': name,
          'phone_number': phoneNumber,
        }),
      );

      final data = _handleResponse(response);

      // Store token if registration successful
      if (data['access_token'] != null) {
        setAuthToken(data['access_token']);
        await _saveTokenToStorage(data['access_token']);
      }

      return data;
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  /// Login user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/login'),
        headers: await _getHeaders(requireAuth: false),
        body: json.encode({'email': email, 'password': password}),
      );

      final data = _handleResponse(response);

      // Store token if login successful
      if (data['access_token'] != null) {
        setAuthToken(data['access_token']);
        await _saveTokenToStorage(data['access_token']);
      }

      return data;
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/auth/logout'),
        headers: await _getHeaders(),
      );
    } finally {
      clearAuthToken();
      await _removeTokenFromStorage();
    }
  }

  /// Get current user profile
  Future<User> getCurrentUser() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConstants.baseUrl}/users/profile'),
        headers: await _getHeaders(),
      );

      final data = _handleResponse(response);
      return User.fromJson(data);
    } catch (e) {
      throw Exception('Failed to get user profile: $e');
    }
  }

  /// Update user profile
  Future<User> updateProfile(Map<String, dynamic> profileData) async {
    try {
      final response = await _client.put(
        Uri.parse('${ApiConstants.baseUrl}/users/profile'),
        headers: await _getHeaders(),
        body: json.encode(profileData),
      );

      final data = _handleResponse(response);
      return User.fromJson(data);
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  // =============================================================================
  // EMERGENCY RESPONSE
  // =============================================================================

  /// Send emergency alert
  Future<Map<String, dynamic>> sendEmergencyAlert({
    required String alertType,
    required List<String> recipientIds,
    Map<String, dynamic>? locationData,
    String? additionalInfo,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/emergency-alert'),
        headers: await _getHeaders(),
        body: json.encode({
          'alert_type': alertType,
          'recipient_ids': recipientIds,
          'location_data': locationData,
          'additional_info': additionalInfo,
        }),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Failed to send emergency alert: $e');
    }
  }

  /// Get emergency contacts
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConstants.baseUrl}/users/emergency-contacts'),
        headers: await _getHeaders(),
      );

      final data = _handleResponse(response);
      return List<Map<String, dynamic>>.from(data['contacts'] ?? []);
    } catch (e) {
      throw Exception('Failed to get emergency contacts: $e');
    }
  }

  /// Add emergency contact
  Future<void> addEmergencyContact({
    required String name,
    required String phoneNumber,
    String? relationship,
  }) async {
    try {
      await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/users/emergency-contacts'),
        headers: await _getHeaders(),
        body: json.encode({
          'name': name,
          'phone_number': phoneNumber,
          'relationship': relationship,
        }),
      );
    } catch (e) {
      throw Exception('Failed to add emergency contact: $e');
    }
  }

  // =============================================================================
  // THREAT ANALYSIS
  // =============================================================================

  /// Submit motion data for analysis
  Future<Map<String, dynamic>> analyzeMotion({
    required List<Map<String, dynamic>> sensorData,
    Map<String, dynamic>? deviceInfo,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/threats/analyze-motion'),
        headers: await _getHeaders(),
        body: json.encode({
          'sensor_data': sensorData,
          'device_info': deviceInfo,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Motion analysis failed: $e');
    }
  }

  /// Submit image for vision analysis
  Future<Map<String, dynamic>> analyzeVision({
    required String imageData, // base64 encoded
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/threats/analyze-vision'),
        headers: await _getHeaders(),
        body: json.encode({
          'image_data': imageData,
          'metadata': metadata,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Vision analysis failed: $e');
    }
  }

  /// Get threat analysis results
  Future<List<ThreatAnalysis>> getThreatAnalyses({
    int limit = 20,
    int offset = 0,
    String? threatType,
  }) async {
    try {
      final queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (threatType != null) 'threat_type': threatType,
      };

      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/threats/analyses',
      ).replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: await _getHeaders());

      final data = _handleResponse(response);
      final analyses = List<Map<String, dynamic>>.from(data['analyses'] ?? []);

      return analyses.map((json) => ThreatAnalysis.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to get threat analyses: $e');
    }
  }

  // =============================================================================
  // EVIDENCE STORAGE
  // =============================================================================

  /// Upload evidence file
  Future<Map<String, dynamic>> uploadEvidence({
    required Uint8List fileBytes,
    required String fileName,
    required String evidenceType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}/evidence/upload'),
      );

      // Add headers
      final headers = await _getHeaders();
      request.headers.addAll(headers);

      // Add file
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );

      // Add fields
      request.fields['evidence_type'] = evidenceType;
      if (metadata != null) {
        request.fields['metadata'] = json.encode(metadata);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Evidence upload failed: $e');
    }
  }

  /// Get user's evidence
  Future<List<EvidenceData>> getEvidence({
    int limit = 20,
    int offset = 0,
    String? evidenceType,
  }) async {
    try {
      final queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (evidenceType != null) 'evidence_type': evidenceType,
      };

      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/evidence',
      ).replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: await _getHeaders());

      final data = _handleResponse(response);
      final evidenceList = List<Map<String, dynamic>>.from(
        data['evidence'] ?? [],
      );

      return evidenceList.map((json) => EvidenceData.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to get evidence: $e');
    }
  }

  /// Get evidence download URL
  Future<String> getEvidenceDownloadUrl(String evidenceId) async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConstants.baseUrl}/evidence/$evidenceId/download-url'),
        headers: await _getHeaders(),
      );

      final data = _handleResponse(response);
      return data['download_url'];
    } catch (e) {
      throw Exception('Failed to get evidence download URL: $e');
    }
  }

  // =============================================================================
  // COMMUNICATION
  // =============================================================================

  /// Get user's chat rooms
  Future<List<ChatRoom>> getChatRooms({
    String? roomType,
    bool includeArchived = false,
  }) async {
    try {
      final queryParams = <String, String>{
        'include_archived': includeArchived.toString(),
        if (roomType != null) 'room_type': roomType,
      };

      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/chat-rooms',
      ).replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: await _getHeaders());

      final data = _handleResponse(response);
      final rooms = List<Map<String, dynamic>>.from(data['chat_rooms'] ?? []);

      return rooms.map((json) => ChatRoom.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to get chat rooms: $e');
    }
  }

  /// Create chat room
  Future<String> createChatRoom({
    required String name,
    required String roomType,
    required List<String> participantIds,
    String? description,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/chat-rooms'),
        headers: await _getHeaders(),
        body: json.encode({
          'name': name,
          'room_type': roomType,
          'participant_ids': participantIds,
          'description': description,
        }),
      );

      final data = _handleResponse(response);
      return data['chat_room_id'];
    } catch (e) {
      throw Exception('Failed to create chat room: $e');
    }
  }

  /// Send message to chat room
  Future<String> sendMessage({
    required String chatRoomId,
    required String messageText,
    String messageType = 'text',
    List<String>? mediaUrls,
    Map<String, dynamic>? locationData,
    String? replyToMessageId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConstants.baseUrl}/chat-rooms/$chatRoomId/messages'),
        headers: await _getHeaders(),
        body: json.encode({
          'message_text': messageText,
          'message_type': messageType,
          'media_urls': mediaUrls,
          'location_data': locationData,
          'reply_to_message_id': replyToMessageId,
        }),
      );

      final data = _handleResponse(response);
      return data['message_id'];
    } catch (e) {
      throw Exception('Failed to send message: $e');
    }
  }

  /// Get chat room messages
  Future<List<Message>> getChatRoomMessages({
    required String chatRoomId,
    int limit = 50,
    int offset = 0,
    String? messageType,
  }) async {
    try {
      final queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
        if (messageType != null) 'message_type': messageType,
      };

      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/chat-rooms/$chatRoomId/messages',
      ).replace(queryParameters: queryParams);

      final response = await _client.get(uri, headers: await _getHeaders());

      final data = _handleResponse(response);
      final messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);

      return messages.map((json) => Message.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to get messages: $e');
    }
  }

  /// Mark message as read
  Future<void> markMessageAsRead({
    required String chatRoomId,
    required String messageId,
  }) async {
    try {
      await _client.post(
        Uri.parse(
          '${ApiConstants.baseUrl}/chat-rooms/$chatRoomId/messages/$messageId/read',
        ),
        headers: await _getHeaders(),
      );
    } catch (e) {
      throw Exception('Failed to mark message as read: $e');
    }
  }

  // =============================================================================
  // HEALTH AND MONITORING
  // =============================================================================

  /// Check API Gateway health
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConstants.baseUrl}/health'),
        headers: await _getHeaders(requireAuth: false),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Health check failed: $e');
    }
  }

  /// Check services health
  Future<Map<String, dynamic>> checkServicesHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('${ApiConstants.baseUrl}/services/health'),
        headers: await _getHeaders(requireAuth: false),
      );
      return _handleResponse(response);
    } catch (e) {
      throw Exception('Services health check failed: $e');
    }
  }

  // =============================================================================
  // TOKEN MANAGEMENT
  // =============================================================================

  /// Load token from storage
  Future<void> loadTokenFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token != null) {
        setAuthToken(token);
      }
    } catch (e) {
      // Ignore errors loading token
    }
  }

  /// Save token to storage
  Future<void> _saveTokenToStorage(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
    } catch (e) {
      // Ignore errors saving token
    }
  }

  /// Remove token from storage
  Future<void> _removeTokenFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (e) {
      // Ignore errors removing token
    }
  }

  // =============================================================================
  // CLEANUP
  // =============================================================================

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;

  ApiException({required this.message, required this.statusCode, this.details});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}
