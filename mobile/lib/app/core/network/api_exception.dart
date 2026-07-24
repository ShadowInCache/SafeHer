class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  const ApiException({required this.message, this.statusCode, this.details});

  @override
  String toString() {
    return 'ApiException(statusCode: $statusCode, message: $message, details: $details)';
  }
}
