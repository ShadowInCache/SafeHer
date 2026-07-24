import 'package:json_annotation/json_annotation.dart';

part 'threat_analysis.g.dart';

@JsonSerializable()
class ThreatAnalysis {
  final String id;
  final String userId;
  final String inputType;
  final String threatLevel;
  final double confidenceScore;
  final Map<String, dynamic> inputData;
  final Map<String, dynamic> analysisResults;
  final List<ThreatIndicator> indicators;
  final List<String> recommendations;
  final String status;
  final DateTime createdAt;
  final DateTime? processedAt;
  final Map<String, dynamic> metadata;

  ThreatAnalysis({
    required this.id,
    required this.userId,
    required this.inputType,
    required this.threatLevel,
    required this.confidenceScore,
    required this.inputData,
    required this.analysisResults,
    required this.indicators,
    required this.recommendations,
    required this.status,
    required this.createdAt,
    this.processedAt,
    this.metadata = const {},
  });

  factory ThreatAnalysis.fromJson(Map<String, dynamic> json) =>
      _$ThreatAnalysisFromJson(json);
  Map<String, dynamic> toJson() => _$ThreatAnalysisToJson(this);

  bool get isHighThreat => threatLevel == 'high' || threatLevel == 'critical';
  bool get isProcessed => processedAt != null;

  String get threatLevelDisplay {
    switch (threatLevel.toLowerCase()) {
      case 'low':
        return 'Low Risk';
      case 'medium':
        return 'Medium Risk';
      case 'high':
        return 'High Risk';
      case 'critical':
        return 'Critical Risk';
      default:
        return 'Unknown';
    }
  }
}

@JsonSerializable()
class ThreatIndicator {
  final String type;
  final String category;
  final String description;
  final double confidence;
  final Map<String, dynamic> details;
  final String severity;

  ThreatIndicator({
    required this.type,
    required this.category,
    required this.description,
    required this.confidence,
    required this.details,
    required this.severity,
  });

  factory ThreatIndicator.fromJson(Map<String, dynamic> json) =>
      _$ThreatIndicatorFromJson(json);
  Map<String, dynamic> toJson() => _$ThreatIndicatorToJson(this);
}

@JsonSerializable()
class MotionAnalysisInput {
  final List<SensorReading> sensorData;
  final DeviceInfo deviceInfo;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  MotionAnalysisInput({
    required this.sensorData,
    required this.deviceInfo,
    required this.timestamp,
    this.metadata,
  });

  factory MotionAnalysisInput.fromJson(Map<String, dynamic> json) =>
      _$MotionAnalysisInputFromJson(json);
  Map<String, dynamic> toJson() => _$MotionAnalysisInputToJson(this);
}

@JsonSerializable()
class SensorReading {
  final double x;
  final double y;
  final double z;
  final DateTime timestamp;
  final String sensorType;

  SensorReading({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
    required this.sensorType,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) =>
      _$SensorReadingFromJson(json);
  Map<String, dynamic> toJson() => _$SensorReadingToJson(this);
}

@JsonSerializable()
class VisionAnalysisInput {
  final String imageData; // base64 encoded
  final ImageMetadata metadata;
  final DateTime timestamp;

  VisionAnalysisInput({
    required this.imageData,
    required this.metadata,
    required this.timestamp,
  });

  factory VisionAnalysisInput.fromJson(Map<String, dynamic> json) =>
      _$VisionAnalysisInputFromJson(json);
  Map<String, dynamic> toJson() => _$VisionAnalysisInputToJson(this);
}

@JsonSerializable()
class ImageMetadata {
  final int width;
  final int height;
  final String format;
  final int? fileSize;
  final LocationData? location;
  final String? cameraId;

  ImageMetadata({
    required this.width,
    required this.height,
    required this.format,
    this.fileSize,
    this.location,
    this.cameraId,
  });

  factory ImageMetadata.fromJson(Map<String, dynamic> json) =>
      _$ImageMetadataFromJson(json);
  Map<String, dynamic> toJson() => _$ImageMetadataToJson(this);
}

@JsonSerializable()
class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final DateTime timestamp;
  final String? address;

  LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    required this.timestamp,
    this.address,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) =>
      _$LocationDataFromJson(json);
  Map<String, dynamic> toJson() => _$LocationDataToJson(this);
}

@JsonSerializable()
class DeviceInfo {
  final String deviceId;
  final String deviceType;
  final String platform;
  final String appVersion;
  final String osVersion;
  final Map<String, dynamic> capabilities;

  DeviceInfo({
    required this.deviceId,
    required this.deviceType,
    required this.platform,
    required this.appVersion,
    required this.osVersion,
    this.capabilities = const {},
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);
}

@JsonSerializable()
class ThreatAnalysisReport {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final List<ThreatAnalysis> analyses;
  final ThreatSummary summary;
  final List<String> recommendations;

  ThreatAnalysisReport({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.analyses,
    required this.summary,
    required this.recommendations,
  });

  factory ThreatAnalysisReport.fromJson(Map<String, dynamic> json) =>
      _$ThreatAnalysisReportFromJson(json);
  Map<String, dynamic> toJson() => _$ThreatAnalysisReportToJson(this);
}

@JsonSerializable()
class ThreatSummary {
  final int totalAnalyses;
  final int lowThreatCount;
  final int mediumThreatCount;
  final int highThreatCount;
  final int criticalThreatCount;
  final double averageConfidence;
  final List<String> topThreatTypes;

  ThreatSummary({
    required this.totalAnalyses,
    required this.lowThreatCount,
    required this.mediumThreatCount,
    required this.highThreatCount,
    required this.criticalThreatCount,
    required this.averageConfidence,
    required this.topThreatTypes,
  });

  factory ThreatSummary.fromJson(Map<String, dynamic> json) =>
      _$ThreatSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$ThreatSummaryToJson(this);

  int get totalThreatCount =>
      lowThreatCount +
      mediumThreatCount +
      highThreatCount +
      criticalThreatCount;

  double get threatPercentage =>
      totalAnalyses > 0 ? (totalThreatCount / totalAnalyses) * 100 : 0.0;
}
