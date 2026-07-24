import 'package:json_annotation/json_annotation.dart';

part 'evidence_data.g.dart';

@JsonSerializable()
class EvidenceData {
  final String evidenceId;
  final String userId;
  final String? emergencyId;
  final String evidenceType;
  final String filePath;
  final String? encryptionKey;
  final int fileSize;
  final String mimeType;
  final DateTime capturedAt;
  final DateTime storedAt;
  final Map<String, dynamic> metadata;
  final String status;
  final Map<String, dynamic> location;
  final String? deviceSource;
  final int? duration;
  final Map<String, dynamic>? analysisResults;

  const EvidenceData({
    required this.evidenceId,
    required this.userId,
    this.emergencyId,
    required this.evidenceType,
    required this.filePath,
    this.encryptionKey,
    required this.fileSize,
    required this.mimeType,
    required this.capturedAt,
    required this.storedAt,
    required this.metadata,
    required this.status,
    required this.location,
    this.deviceSource,
    this.duration,
    this.analysisResults,
  });

  factory EvidenceData.fromJson(Map<String, dynamic> json) =>
      _$EvidenceDataFromJson(json);
  Map<String, dynamic> toJson() => _$EvidenceDataToJson(this);

  /// Check if evidence is ready for viewing
  bool get isReady => status == 'READY';

  /// Check if evidence is still being processed
  bool get isProcessing => status == 'UPLOADING' || status == 'PROCESSING';

  /// Check if there was an error with the evidence
  bool get hasError => status == 'ERROR';

  /// Get human-readable file size
  String get formattedFileSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Get formatted duration for media files
  String? get formattedDuration {
    if (duration == null) return null;

    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get evidence type display name
  String get typeDisplayName {
    switch (evidenceType.toUpperCase()) {
      case 'VIDEO':
        return 'Video Recording';
      case 'AUDIO':
        return 'Audio Recording';
      case 'PHOTO':
        return 'Photograph';
      case 'SENSOR_DATA':
        return 'Sensor Data';
      case 'GPS_TRACK':
        return 'GPS Tracking';
      default:
        return evidenceType;
    }
  }

  /// Get device source display name
  String get deviceDisplayName {
    switch (deviceSource?.toLowerCase()) {
      case 'glove':
        return 'Smart Glove';
      case 'glasses':
        return 'Smart Glasses';
      case 'mobile_app':
        return 'Mobile App';
      case 'emergency_button':
        return 'Emergency Button';
      default:
        return deviceSource ?? 'Unknown Device';
    }
  }

  /// Get location string
  String get locationString {
    final lat = location['latitude'];
    final lng = location['longitude'];
    final address = location['address'];

    if (address != null && address.toString().isNotEmpty) {
      return address.toString();
    } else if (lat != null && lng != null) {
      return 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';
    } else {
      return 'Location unknown';
    }
  }

  /// Check if evidence contains threat analysis
  bool get hasAnalysis =>
      analysisResults != null && analysisResults!.isNotEmpty;

  /// Get threat level from analysis (if available)
  String? get threatLevel {
    if (!hasAnalysis) return null;
    return analysisResults!['threat_level']?.toString();
  }

  /// Get confidence score from analysis (if available)
  double? get confidenceScore {
    if (!hasAnalysis) return null;
    final score = analysisResults!['confidence_score'];
    return score?.toDouble();
  }

  /// Check if evidence is related to an emergency
  bool get isEmergencyEvidence => emergencyId != null;

  /// Get time since evidence was captured
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(capturedAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  /// Create a copy with updated fields
  EvidenceData copyWith({
    String? evidenceId,
    String? userId,
    String? emergencyId,
    String? evidenceType,
    String? filePath,
    String? encryptionKey,
    int? fileSize,
    String? mimeType,
    DateTime? capturedAt,
    DateTime? storedAt,
    Map<String, dynamic>? metadata,
    String? status,
    Map<String, dynamic>? location,
    String? deviceSource,
    int? duration,
    Map<String, dynamic>? analysisResults,
  }) {
    return EvidenceData(
      evidenceId: evidenceId ?? this.evidenceId,
      userId: userId ?? this.userId,
      emergencyId: emergencyId ?? this.emergencyId,
      evidenceType: evidenceType ?? this.evidenceType,
      filePath: filePath ?? this.filePath,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      capturedAt: capturedAt ?? this.capturedAt,
      storedAt: storedAt ?? this.storedAt,
      metadata: metadata ?? this.metadata,
      status: status ?? this.status,
      location: location ?? this.location,
      deviceSource: deviceSource ?? this.deviceSource,
      duration: duration ?? this.duration,
      analysisResults: analysisResults ?? this.analysisResults,
    );
  }

  @override
  String toString() {
    return 'EvidenceData(id: $evidenceId, type: $evidenceType, status: $status, size: $formattedFileSize)';
  }
}
