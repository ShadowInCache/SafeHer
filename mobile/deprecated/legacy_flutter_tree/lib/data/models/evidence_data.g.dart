// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'evidence_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EvidenceData _$EvidenceDataFromJson(Map<String, dynamic> json) => EvidenceData(
  evidenceId: json['evidenceId'] as String,
  userId: json['userId'] as String,
  emergencyId: json['emergencyId'] as String?,
  evidenceType: json['evidenceType'] as String,
  filePath: json['filePath'] as String,
  encryptionKey: json['encryptionKey'] as String?,
  fileSize: (json['fileSize'] as num).toInt(),
  mimeType: json['mimeType'] as String,
  capturedAt: DateTime.parse(json['capturedAt'] as String),
  storedAt: DateTime.parse(json['storedAt'] as String),
  metadata: json['metadata'] as Map<String, dynamic>,
  status: json['status'] as String,
  location: json['location'] as Map<String, dynamic>,
  deviceSource: json['deviceSource'] as String?,
  duration: (json['duration'] as num?)?.toInt(),
  analysisResults: json['analysisResults'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$EvidenceDataToJson(EvidenceData instance) =>
    <String, dynamic>{
      'evidenceId': instance.evidenceId,
      'userId': instance.userId,
      'emergencyId': instance.emergencyId,
      'evidenceType': instance.evidenceType,
      'filePath': instance.filePath,
      'encryptionKey': instance.encryptionKey,
      'fileSize': instance.fileSize,
      'mimeType': instance.mimeType,
      'capturedAt': instance.capturedAt.toIso8601String(),
      'storedAt': instance.storedAt.toIso8601String(),
      'metadata': instance.metadata,
      'status': instance.status,
      'location': instance.location,
      'deviceSource': instance.deviceSource,
      'duration': instance.duration,
      'analysisResults': instance.analysisResults,
    };
