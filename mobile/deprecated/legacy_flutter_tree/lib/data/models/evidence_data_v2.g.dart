// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'evidence_data_v2.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EvidenceDataV2 _$EvidenceDataV2FromJson(Map<String, dynamic> json) =>
    EvidenceDataV2(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      evidenceType: json['evidenceType'] as String,
      files: (json['files'] as List<dynamic>)
          .map((e) => FileRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      accessLevel: json['accessLevel'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sharedWith:
          (json['sharedWith'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      status: json['status'] as String,
    );

Map<String, dynamic> _$EvidenceDataV2ToJson(EvidenceDataV2 instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'title': instance.title,
      'description': instance.description,
      'evidenceType': instance.evidenceType,
      'files': instance.files,
      'accessLevel': instance.accessLevel,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'sharedWith': instance.sharedWith,
      'metadata': instance.metadata,
      'tags': instance.tags,
      'status': instance.status,
    };

FileRecord _$FileRecordFromJson(Map<String, dynamic> json) => FileRecord(
  id: json['id'] as String,
  filename: json['filename'] as String,
  contentType: json['contentType'] as String,
  size: (json['size'] as num?)?.toInt(),
  storageLocation: json['storageLocation'] as String,
  isEncrypted: json['isEncrypted'] as bool,
  checksum: json['checksum'] as String,
  uploadedAt: DateTime.parse(json['uploadedAt'] as String),
  metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$FileRecordToJson(FileRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'filename': instance.filename,
      'contentType': instance.contentType,
      'size': instance.size,
      'storageLocation': instance.storageLocation,
      'isEncrypted': instance.isEncrypted,
      'checksum': instance.checksum,
      'uploadedAt': instance.uploadedAt.toIso8601String(),
      'metadata': instance.metadata,
    };
