// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'threat_analysis.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ThreatAnalysis _$ThreatAnalysisFromJson(Map<String, dynamic> json) =>
    ThreatAnalysis(
      id: json['id'] as String,
      userId: json['userId'] as String,
      inputType: json['inputType'] as String,
      threatLevel: json['threatLevel'] as String,
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      inputData: json['inputData'] as Map<String, dynamic>,
      analysisResults: json['analysisResults'] as Map<String, dynamic>,
      indicators: (json['indicators'] as List<dynamic>)
          .map((e) => ThreatIndicator.fromJson(e as Map<String, dynamic>))
          .toList(),
      recommendations: (json['recommendations'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      processedAt: json['processedAt'] == null
          ? null
          : DateTime.parse(json['processedAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$ThreatAnalysisToJson(ThreatAnalysis instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'inputType': instance.inputType,
      'threatLevel': instance.threatLevel,
      'confidenceScore': instance.confidenceScore,
      'inputData': instance.inputData,
      'analysisResults': instance.analysisResults,
      'indicators': instance.indicators,
      'recommendations': instance.recommendations,
      'status': instance.status,
      'createdAt': instance.createdAt.toIso8601String(),
      'processedAt': instance.processedAt?.toIso8601String(),
      'metadata': instance.metadata,
    };

ThreatIndicator _$ThreatIndicatorFromJson(Map<String, dynamic> json) =>
    ThreatIndicator(
      type: json['type'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      details: json['details'] as Map<String, dynamic>,
      severity: json['severity'] as String,
    );

Map<String, dynamic> _$ThreatIndicatorToJson(ThreatIndicator instance) =>
    <String, dynamic>{
      'type': instance.type,
      'category': instance.category,
      'description': instance.description,
      'confidence': instance.confidence,
      'details': instance.details,
      'severity': instance.severity,
    };

MotionAnalysisInput _$MotionAnalysisInputFromJson(Map<String, dynamic> json) =>
    MotionAnalysisInput(
      sensorData: (json['sensorData'] as List<dynamic>)
          .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
          .toList(),
      deviceInfo: DeviceInfo.fromJson(
        json['deviceInfo'] as Map<String, dynamic>,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$MotionAnalysisInputToJson(
  MotionAnalysisInput instance,
) => <String, dynamic>{
  'sensorData': instance.sensorData,
  'deviceInfo': instance.deviceInfo,
  'timestamp': instance.timestamp.toIso8601String(),
  'metadata': instance.metadata,
};

SensorReading _$SensorReadingFromJson(Map<String, dynamic> json) =>
    SensorReading(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      sensorType: json['sensorType'] as String,
    );

Map<String, dynamic> _$SensorReadingToJson(SensorReading instance) =>
    <String, dynamic>{
      'x': instance.x,
      'y': instance.y,
      'z': instance.z,
      'timestamp': instance.timestamp.toIso8601String(),
      'sensorType': instance.sensorType,
    };

VisionAnalysisInput _$VisionAnalysisInputFromJson(Map<String, dynamic> json) =>
    VisionAnalysisInput(
      imageData: json['imageData'] as String,
      metadata: ImageMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$VisionAnalysisInputToJson(
  VisionAnalysisInput instance,
) => <String, dynamic>{
  'imageData': instance.imageData,
  'metadata': instance.metadata,
  'timestamp': instance.timestamp.toIso8601String(),
};

ImageMetadata _$ImageMetadataFromJson(Map<String, dynamic> json) =>
    ImageMetadata(
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      format: json['format'] as String,
      fileSize: (json['fileSize'] as num?)?.toInt(),
      location: json['location'] == null
          ? null
          : LocationData.fromJson(json['location'] as Map<String, dynamic>),
      cameraId: json['cameraId'] as String?,
    );

Map<String, dynamic> _$ImageMetadataToJson(ImageMetadata instance) =>
    <String, dynamic>{
      'width': instance.width,
      'height': instance.height,
      'format': instance.format,
      'fileSize': instance.fileSize,
      'location': instance.location,
      'cameraId': instance.cameraId,
    };

LocationData _$LocationDataFromJson(Map<String, dynamic> json) => LocationData(
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
  accuracy: (json['accuracy'] as num?)?.toDouble(),
  altitude: (json['altitude'] as num?)?.toDouble(),
  timestamp: DateTime.parse(json['timestamp'] as String),
  address: json['address'] as String?,
);

Map<String, dynamic> _$LocationDataToJson(LocationData instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'accuracy': instance.accuracy,
      'altitude': instance.altitude,
      'timestamp': instance.timestamp.toIso8601String(),
      'address': instance.address,
    };

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
  deviceId: json['deviceId'] as String,
  deviceType: json['deviceType'] as String,
  platform: json['platform'] as String,
  appVersion: json['appVersion'] as String,
  osVersion: json['osVersion'] as String,
  capabilities: json['capabilities'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'deviceType': instance.deviceType,
      'platform': instance.platform,
      'appVersion': instance.appVersion,
      'osVersion': instance.osVersion,
      'capabilities': instance.capabilities,
    };

ThreatAnalysisReport _$ThreatAnalysisReportFromJson(
  Map<String, dynamic> json,
) => ThreatAnalysisReport(
  id: json['id'] as String,
  startTime: DateTime.parse(json['startTime'] as String),
  endTime: DateTime.parse(json['endTime'] as String),
  analyses: (json['analyses'] as List<dynamic>)
      .map((e) => ThreatAnalysis.fromJson(e as Map<String, dynamic>))
      .toList(),
  summary: ThreatSummary.fromJson(json['summary'] as Map<String, dynamic>),
  recommendations: (json['recommendations'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$ThreatAnalysisReportToJson(
  ThreatAnalysisReport instance,
) => <String, dynamic>{
  'id': instance.id,
  'startTime': instance.startTime.toIso8601String(),
  'endTime': instance.endTime.toIso8601String(),
  'analyses': instance.analyses,
  'summary': instance.summary,
  'recommendations': instance.recommendations,
};

ThreatSummary _$ThreatSummaryFromJson(Map<String, dynamic> json) =>
    ThreatSummary(
      totalAnalyses: (json['totalAnalyses'] as num).toInt(),
      lowThreatCount: (json['lowThreatCount'] as num).toInt(),
      mediumThreatCount: (json['mediumThreatCount'] as num).toInt(),
      highThreatCount: (json['highThreatCount'] as num).toInt(),
      criticalThreatCount: (json['criticalThreatCount'] as num).toInt(),
      averageConfidence: (json['averageConfidence'] as num).toDouble(),
      topThreatTypes: (json['topThreatTypes'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$ThreatSummaryToJson(ThreatSummary instance) =>
    <String, dynamic>{
      'totalAnalyses': instance.totalAnalyses,
      'lowThreatCount': instance.lowThreatCount,
      'mediumThreatCount': instance.mediumThreatCount,
      'highThreatCount': instance.highThreatCount,
      'criticalThreatCount': instance.criticalThreatCount,
      'averageConfidence': instance.averageConfidence,
      'topThreatTypes': instance.topThreatTypes,
    };
