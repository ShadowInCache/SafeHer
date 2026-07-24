import 'package:json_annotation/json_annotation.dart';

part 'evidence_data_v2.g.dart';

@JsonSerializable()
class EvidenceDataV2 {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String evidenceType;
  final List<FileRecord> files;
  final String accessLevel;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> sharedWith;
  final Map<String, dynamic> metadata;
  final List<String> tags;
  final String status;

  EvidenceDataV2({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    required this.evidenceType,
    required this.files,
    required this.accessLevel,
    required this.createdAt,
    required this.updatedAt,
    this.sharedWith = const [],
    this.metadata = const {},
    this.tags = const [],
    required this.status,
  });

  factory EvidenceDataV2.fromJson(Map<String, dynamic> json) =>
      _$EvidenceDataV2FromJson(json);
  Map<String, dynamic> toJson() => _$EvidenceDataV2ToJson(this);

  bool get isShared => sharedWith.isNotEmpty;
  bool get isActive => status == 'active';
  bool get hasFiles => files.isNotEmpty;

  int get totalFileSize => files.fold(0, (sum, file) => sum + (file.size ?? 0));

  String get evidenceTypeDisplay {
    switch (evidenceType.toLowerCase()) {
      case 'photo':
        return '📷 Photo Evidence';
      case 'video':
        return '🎥 Video Evidence';
      case 'audio':
        return '🎤 Audio Evidence';
      case 'document':
        return '📄 Document Evidence';
      case 'screenshot':
        return '📱 Screenshot';
      case 'emergency_recording':
        return '🚨 Emergency Recording';
      default:
        return '📎 Evidence';
    }
  }

  String get accessLevelDisplay {
    switch (accessLevel.toLowerCase()) {
      case 'private':
        return '🔒 Private';
      case 'emergency_contacts':
        return '👥 Emergency Contacts';
      case 'authorities':
        return '🚔 Authorities';
      case 'public':
        return '🌐 Public';
      default:
        return '🔒 Private';
    }
  }
}

@JsonSerializable()
class FileRecord {
  final String id;
  final String filename;
  final String contentType;
  final int? size;
  final String storageLocation;
  final bool isEncrypted;
  final String checksum;
  final DateTime uploadedAt;
  final Map<String, dynamic> metadata;

  FileRecord({
    required this.id,
    required this.filename,
    required this.contentType,
    this.size,
    required this.storageLocation,
    required this.isEncrypted,
    required this.checksum,
    required this.uploadedAt,
    this.metadata = const {},
  });

  factory FileRecord.fromJson(Map<String, dynamic> json) =>
      _$FileRecordFromJson(json);
  Map<String, dynamic> toJson() => _$FileRecordToJson(this);

  bool get isImage => contentType.startsWith('image/');
  bool get isVideo => contentType.startsWith('video/');
  bool get isAudio => contentType.startsWith('audio/');
  bool get isDocument =>
      contentType.startsWith('application/') || contentType.startsWith('text/');

  String get fileExtension {
    final parts = filename.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String get displaySize {
    if (size == null) return 'Unknown size';

    final bytes = size!;
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  String get fileTypeIcon {
    if (isImage) return '🖼️';
    if (isVideo) return '🎥';
    if (isAudio) return '🎵';
    if (isDocument) return '📄';
    return '📎';
  }
}
