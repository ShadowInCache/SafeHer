import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/services/websocket_service_v2.dart';
import '../../data/services/api_service_v2.dart';
import '../../data/models/threat_update.dart';
import '../../data/models/emergency_alert.dart';
import '../../data/models/evidence_data.dart';

final emergencyProvider = ChangeNotifierProvider<EmergencyProvider>((ref) {
  final webSocketService = ref.read(webSocketServiceV2Provider);
  final apiService = ref.read(apiServiceProvider);
  return EmergencyProvider(webSocketService, apiService);
});

/// Provider for managing emergency state and real-time threat monitoring
class EmergencyProvider extends ChangeNotifier {
  final WebSocketServiceV2 _webSocketService;
  final ApiService _apiService;

  // User and connection state
  String? _userId;
  bool _isConnected = false;
  bool _isEmergencyMode = false;
  Position? _currentLocation;

  // Real-time data
  ThreatUpdate? _latestThreatUpdate;
  final List<EmergencyAlert> _emergencyAlerts = [];
  final List<EvidenceData> _evidenceData = [];
  final Map<String, dynamic> _systemStatus = {};
  final List<Map<String, dynamic>> _connectedDevices = [];
  List<Map<String, dynamic>> _emergencyContacts = [];

  // Subscriptions for real-time updates
  StreamSubscription? _messageSubscription;
  StreamSubscription? _alertSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _errorSubscription;
  Timer? _locationUpdateTimer;

  EmergencyProvider(this._webSocketService, this._apiService);

  // Getters
  String? get userId => _userId;
  bool get isConnected => _isConnected;
  bool get isEmergencyMode => _isEmergencyMode;
  Position? get currentLocation => _currentLocation;
  ThreatUpdate? get latestThreatUpdate => _latestThreatUpdate;
  List<EmergencyAlert> get emergencyAlerts => _emergencyAlerts;
  List<EvidenceData> get evidenceData => _evidenceData;
  Map<String, dynamic> get systemStatus => _systemStatus;
  List<Map<String, dynamic>> get connectedDevices => _connectedDevices;
  List<Map<String, dynamic>> get emergencyContacts => _emergencyContacts;
  bool get hasActiveThreat =>
      _latestThreatUpdate != null && _latestThreatUpdate!.isHighPriority;

  /// Initialize emergency monitoring for a user
  Future<void> initialize(String userId) async {
    try {
      _userId = userId;

      // Connect WebSocket
      await _webSocketService.connect(userId);
      _isConnected = true;

      // Subscribe to WebSocket streams
      _subscribeToWebSocketStreams();

      // Load initial data
      await _loadInitialData();

      // Start periodic location updates
      _startLocationTracking();

      notifyListeners();
    } catch (e) {
      _isConnected = false;
      notifyListeners();
      throw Exception('Failed to initialize emergency provider: $e');
    }
  }

  /// Send emergency alert
  Future<void> triggerEmergency({
    String? additionalInfo,
    List<String>? recipientIds,
  }) async {
    try {
      _isEmergencyMode = true;
      notifyListeners();

      final location = await _getCurrentLocationMap();

      // Send emergency alert through API
      await _apiService.sendEmergencyAlert(
        alertType: 'MANUAL',
        recipientIds: recipientIds ?? [],
        locationData: location,
        additionalInfo: additionalInfo,
      );

      notifyListeners();
    } catch (e) {
      _isEmergencyMode = false;
      notifyListeners();
      throw Exception('Failed to trigger emergency: $e');
    }
  }

  /// Load emergency contacts
  Future<List<Map<String, dynamic>>> loadEmergencyContacts() async {
    try {
      final contacts = await _apiService.getEmergencyContacts();
      _emergencyContacts = contacts;
      notifyListeners();
      return contacts;
    } catch (e) {
      throw Exception('Failed to load contacts: $e');
    }
  }

  /// Add emergency contact
  Future<void> addEmergencyContact({
    required String name,
    required String phoneNumber,
    String? relationship,
  }) async {
    try {
      await _apiService.addEmergencyContact(
        name: name,
        phoneNumber: phoneNumber,
        relationship: relationship,
      );
      await loadEmergencyContacts();
    } catch (e) {
      throw Exception('Failed to add contact: $e');
    }
  }

  /// Load initial data
  Future<void> _loadInitialData() async {
    try {
      // Load emergency contacts
      _emergencyContacts = await _apiService.getEmergencyContacts();
      notifyListeners();
    } catch (e) {
      // Silently fail - non-critical
      debugPrint('Failed to load initial data: $e');
    }
  }

  /// Subscribe to WebSocket streams
  void _subscribeToWebSocketStreams() {
    // Listen for general messages
    _messageSubscription = _webSocketService.messageStream.listen(
      (message) {
        debugPrint('Received message: ${message.content}');
      },
      onError: (error) {
        debugPrint('WebSocket message error: $error');
      },
    );

    // Listen for emergency alerts
    _alertSubscription = _webSocketService.emergencyAlertStream.listen(
      (alert) {
        debugPrint('Received emergency alert');
        notifyListeners();
      },
      onError: (error) {
        debugPrint('WebSocket alert error: $error');
      },
    );

    // Listen for connection status
    _statusSubscription = _webSocketService.statusStream.listen((status) {
      _isConnected = status == WebSocketConnectionStatus.connected;
      notifyListeners();
    });

    // Listen for errors
    _errorSubscription = _webSocketService.errorStream.listen((error) {
      debugPrint('WebSocket error: $error');
    });
  }

  /// Start tracking location
  void _startLocationTracking() {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) async {
      try {
        _currentLocation = await Geolocator.getCurrentPosition();
        notifyListeners();
      } catch (e) {
        debugPrint('Location update failed: $e');
      }
    });
  }

  /// Get current location as a map
  Future<Map<String, dynamic>> _getCurrentLocationMap() async {
    if (_currentLocation != null) {
      return {
        'latitude': _currentLocation!.latitude,
        'longitude': _currentLocation!.longitude,
        'accuracy': _currentLocation!.accuracy,
        'timestamp': _currentLocation!.timestamp.toIso8601String(),
      };
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': position.timestamp.toIso8601String(),
      };
    } catch (e) {
      return {
        'latitude': 0.0,
        'longitude': 0.0,
        'accuracy': 0.0,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _alertSubscription?.cancel();
    _statusSubscription?.cancel();
    _errorSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _webSocketService.disconnect();
    super.dispose();
  }
}
