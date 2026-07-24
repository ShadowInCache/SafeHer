/// API Constants for SafeHer Clean Architecture
///
/// This file contains all API endpoint configurations and constants
/// for communicating with the new microservices architecture.
library;

class ApiConstants {
  // Base Configuration
  static const String baseUrl = 'http://localhost:5000/api/v1';
  static const String websocketUrl = 'ws://localhost:8765/ws';

  // Production URLs (uncomment for production)
  // static const String baseUrl = 'https://api.safeher.com/api/v1';
  // static const String websocketUrl = 'wss://api.safeher.com/ws';

  // Request Configuration
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const int maxRetries = 3;
  static const int rateLimitRetryDelay = 1000; // milliseconds

  // =============================================================================
  // AUTHENTICATION & USER MANAGEMENT ENDPOINTS
  // =============================================================================

  static const String authBase = '/users';

  // Authentication
  static const String registerEndpoint = '$authBase/register';
  static const String loginEndpoint = '$authBase/login';
  static const String logoutEndpoint = '$authBase/logout';
  static const String refreshTokenEndpoint = '$authBase/refresh';
  static const String forgotPasswordEndpoint = '$authBase/forgot-password';
  static const String resetPasswordEndpoint = '$authBase/reset-password';

  // User Profile
  static const String userProfileEndpoint = '$authBase/profile';
  static const String updateProfileEndpoint = '$authBase/profile';
  static const String changePasswordEndpoint = '$authBase/change-password';
  static const String deleteAccountEndpoint = '$authBase/delete-account';

  // Emergency Contacts
  static const String emergencyContactsEndpoint =
      '$authBase/emergency-contacts';
  static String emergencyContactEndpoint(String contactId) =>
      '$emergencyContactsEndpoint/$contactId';

  // Device Registration
  static const String devicesEndpoint = '$authBase/devices';
  static String deviceEndpoint(String deviceId) => '$devicesEndpoint/$deviceId';

  // =============================================================================
  // EMERGENCY RESPONSE ENDPOINTS
  // =============================================================================

  static const String emergencyBase = '/emergency';

  // Emergency Alerts
  static const String emergencyAlertEndpoint = '/emergency-alert';
  static const String emergencyAlertsEndpoint = '$emergencyBase/alerts';
  static String emergencyAlertDetailsEndpoint(String alertId) =>
      '$emergencyAlertsEndpoint/$alertId';
  static String acknowledgeAlertEndpoint(String alertId) =>
      '$emergencyAlertsEndpoint/$alertId/acknowledge';
  static String escalateAlertEndpoint(String alertId) =>
      '$emergencyAlertsEndpoint/$alertId/escalate';

  // Emergency Responses
  static const String emergencyResponsesEndpoint = '$emergencyBase/responses';
  static String emergencyResponseEndpoint(String responseId) =>
      '$emergencyResponsesEndpoint/$responseId';

  // Emergency Contacts Management
  static const String emergencyCallEndpoint = '$emergencyBase/call';
  static const String emergencySmsEndpoint = '$emergencyBase/sms';
  static const String emergencyPushEndpoint = '$emergencyBase/push';

  // =============================================================================
  // THREAT ANALYSIS ENDPOINTS
  // =============================================================================

  static const String threatBase = '/threats';

  // Threat Analysis
  static const String threatAnalysisEndpoint = '$threatBase/analyze';
  static const String threatAnalysesEndpoint = '$threatBase/analyses';
  static String threatAnalysisDetailsEndpoint(String analysisId) =>
      '$threatAnalysesEndpoint/$analysisId';

  // Input Analysis
  static const String analyzeMotionEndpoint = '$threatBase/analyze-motion';
  static const String analyzeVisionEndpoint = '$threatBase/analyze-vision';
  static const String analyzeAudioEndpoint = '$threatBase/analyze-audio';
  static const String analyzeCompositeEndpoint =
      '$threatBase/analyze-composite';

  // Threat Reports
  static const String threatReportsEndpoint = '$threatBase/reports';
  static String threatReportEndpoint(String reportId) =>
      '$threatReportsEndpoint/$reportId';

  // =============================================================================
  // EVIDENCE STORAGE ENDPOINTS
  // =============================================================================

  static const String evidenceBase = '/evidence';

  // Evidence Management
  static const String evidenceEndpoint = evidenceBase;
  static const String evidenceUploadEndpoint = '$evidenceBase/upload';
  static String evidenceDetailsEndpoint(String evidenceId) =>
      '$evidenceBase/$evidenceId';
  static String evidenceDownloadEndpoint(String evidenceId) =>
      '$evidenceBase/$evidenceId/download-url';
  static String evidenceShareEndpoint(String evidenceId) =>
      '$evidenceBase/$evidenceId/share';

  // Evidence Collections
  static const String evidenceCollectionsEndpoint = '$evidenceBase/collections';
  static String evidenceCollectionEndpoint(String collectionId) =>
      '$evidenceCollectionsEndpoint/$collectionId';

  // Evidence Search
  static const String evidenceSearchEndpoint = '$evidenceBase/search';

  // =============================================================================
  // COMMUNICATION ENDPOINTS
  // =============================================================================

  static const String communicationBase = '/chat';

  // Chat Rooms
  static const String chatRoomsEndpoint = '/chat-rooms';
  static String chatRoomEndpoint(String roomId) => '$chatRoomsEndpoint/$roomId';
  static String joinChatRoomEndpoint(String roomId) =>
      '$chatRoomEndpoint($roomId)/join';
  static String leaveChatRoomEndpoint(String roomId) =>
      '$chatRoomEndpoint($roomId)/leave';

  // Messages
  static String chatRoomMessagesEndpoint(String roomId) =>
      '$chatRoomEndpoint($roomId)/messages';
  static String messageEndpoint(String roomId, String messageId) =>
      '${chatRoomMessagesEndpoint(roomId)}/$messageId';
  static String markMessageReadEndpoint(String roomId, String messageId) =>
      '${messageEndpoint(roomId, messageId)}/read';

  // Real-time Communication
  static const String onlineUsersEndpoint = '/online-users';

  // Emergency Communication
  static const String emergencyAlertChatEndpoint = '/emergency-alert-chat';

  // WebSocket Endpoints
  static String communicationWebSocketEndpoint(String userId) =>
      '/communication/$userId';

  // =============================================================================
  // AI SERVICES ENDPOINTS
  // =============================================================================

  static const String aiBase = '/ai';

  // Motion Detection AI
  static const String motionDetectionBase = '$aiBase/motion';
  static const String motionAnalysisEndpoint = '$motionDetectionBase/analyze';
  static const String motionModelHealthEndpoint =
      '$motionDetectionBase/model-health';
  static const String motionHistoryEndpoint = '$motionDetectionBase/history';

  // Vision Analysis AI
  static const String visionAnalysisBase = '$aiBase/vision';
  static const String visionAnalysisEndpoint = '$visionAnalysisBase/analyze';
  static const String visionModelHealthEndpoint =
      '$visionAnalysisBase/model-health';
  static const String visionHistoryEndpoint = '$visionAnalysisBase/history';

  // =============================================================================
  // SYSTEM ENDPOINTS
  // =============================================================================

  // Health Checks
  static const String healthEndpoint = '/health';
  static const String servicesHealthEndpoint = '/services/health';
  static const String systemStatusEndpoint = '/system/status';

  // Metrics and Monitoring
  static const String metricsEndpoint = '/metrics';

  // =============================================================================
  // ERROR CODES
  // =============================================================================

  // HTTP Status Codes
  static const int statusOk = 200;
  static const int statusCreated = 201;
  static const int statusNoContent = 204;
  static const int statusBadRequest = 400;
  static const int statusUnauthorized = 401;
  static const int statusForbidden = 403;
  static const int statusNotFound = 404;
  static const int statusTooManyRequests = 429;
  static const int statusInternalServerError = 500;
  static const int statusServiceUnavailable = 503;
  static const int statusGatewayTimeout = 504;

  // Custom Error Codes
  static const String errorInvalidCredentials = 'INVALID_CREDENTIALS';
  static const String errorTokenExpired = 'TOKEN_EXPIRED';
  static const String errorRateLimitExceeded = 'RATE_LIMIT_EXCEEDED';
  static const String errorServiceUnavailable = 'SERVICE_UNAVAILABLE';
  static const String errorNetworkConnection = 'NETWORK_CONNECTION';
  static const String errorInvalidInput = 'INVALID_INPUT';
  static const String errorFileUploadFailed = 'FILE_UPLOAD_FAILED';
  static const String errorWebSocketConnection = 'WEBSOCKET_CONNECTION';

  // =============================================================================
  // CONFIGURATION METHODS
  // =============================================================================

  /// Get full URL for an endpoint
  static String getFullUrl(String endpoint) {
    if (endpoint.startsWith('/')) {
      return '$baseUrl$endpoint';
    }
    return '$baseUrl/$endpoint';
  }

  /// Get WebSocket URL for an endpoint
  static String getWebSocketUrl(String endpoint) {
    if (endpoint.startsWith('/')) {
      return '$websocketUrl$endpoint';
    }
    return '$websocketUrl/$endpoint';
  }

  /// Check if status code indicates success
  static bool isSuccessStatusCode(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  /// Check if error is retryable
  static bool isRetryableError(int statusCode) {
    return statusCode >= 500 || statusCode == statusTooManyRequests;
  }

  /// Get retry delay for rate limiting
  static Duration getRateLimitRetryDelay() {
    return const Duration(milliseconds: rateLimitRetryDelay);
  }
}

/// Request configuration class
class RequestConfig {
  final Duration timeout;
  final int maxRetries;
  final bool requireAuth;
  final Map<String, String> headers;

  const RequestConfig({
    this.timeout = ApiConstants.requestTimeout,
    this.maxRetries = ApiConstants.maxRetries,
    this.requireAuth = true,
    this.headers = const {},
  });

  /// Configuration for file uploads
  static const RequestConfig upload = RequestConfig(
    timeout: ApiConstants.uploadTimeout,
    maxRetries: 1,
  );

  /// Configuration for real-time requests
  static const RequestConfig realTime = RequestConfig(
    timeout: Duration(seconds: 10),
    maxRetries: 1,
  );

  /// Configuration for public endpoints
  static const RequestConfig public = RequestConfig(requireAuth: false);
}
