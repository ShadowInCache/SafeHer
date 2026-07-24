import 'package:json_annotation/json_annotation.dart';

part 'chat_room.g.dart';

@JsonSerializable()
class ChatRoom {
  final String id;
  final String name;
  final String? description;
  final String roomType;
  final String creatorId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int participantCount;
  final int unreadCount;
  final String? userRole;
  final Message? latestMessage;
  final bool isMuted;
  final Map<String, dynamic> settings;

  ChatRoom({
    required this.id,
    required this.name,
    this.description,
    required this.roomType,
    required this.creatorId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.participantCount,
    required this.unreadCount,
    this.userRole,
    this.latestMessage,
    required this.isMuted,
    this.settings = const {},
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) =>
      _$ChatRoomFromJson(json);
  Map<String, dynamic> toJson() => _$ChatRoomToJson(this);

  bool get hasUnreadMessages => unreadCount > 0;
  bool get isEmergencyRoom => roomType == 'emergency_circle';
  bool get isGroupChat => roomType == 'group';
  bool get isPrivateChat => roomType == 'private';

  String get displayName {
    if (name.isNotEmpty) return name;
    if (isEmergencyRoom) return 'Emergency Circle';
    if (isGroupChat) return 'Group Chat';
    return 'Private Chat';
  }
}

@JsonSerializable()
class Message {
  final String id;
  final String senderId;
  final String messageType;
  final MessageContent content;
  final String status;
  final DateTime createdAt;
  final String? replyToMessageId;
  final LocationData? location;

  Message({
    required this.id,
    required this.senderId,
    required this.messageType,
    required this.content,
    required this.status,
    required this.createdAt,
    this.replyToMessageId,
    this.location,
  });

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  bool get isEmergencyAlert => messageType == 'emergency_alert';
  bool get isPanicSignal => messageType == 'panic_signal';
  bool get hasLocation => location != null;
  bool get hasMedia => content.mediaUrls.isNotEmpty;
  bool get isRead => status == 'read';
  bool get isDelivered => status == 'delivered' || isRead;

  String get messageTypeDisplay {
    switch (messageType) {
      case 'emergency_alert':
        return '🚨 Emergency Alert';
      case 'panic_signal':
        return '🆘 Panic Signal';
      case 'location_share':
        return '📍 Location Shared';
      case 'media':
        return '📎 Media';
      case 'voice_note':
        return '🎤 Voice Note';
      case 'status_update':
        return '📊 Status Update';
      default:
        return 'Message';
    }
  }
}

@JsonSerializable()
class MessageContent {
  final String text;
  final List<String> mediaUrls;
  final Map<String, dynamic> metadata;

  MessageContent({
    required this.text,
    this.mediaUrls = const [],
    this.metadata = const {},
  });

  factory MessageContent.fromJson(Map<String, dynamic> json) =>
      _$MessageContentFromJson(json);
  Map<String, dynamic> toJson() => _$MessageContentToJson(this);

  bool get isEmpty => text.trim().isEmpty && mediaUrls.isEmpty;
  bool get hasText => text.trim().isNotEmpty;
  bool get hasMedia => mediaUrls.isNotEmpty;
}

@JsonSerializable()
class LocationData {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String? address;

  LocationData({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.address,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) =>
      _$LocationDataFromJson(json);
  Map<String, dynamic> toJson() => _$LocationDataToJson(this);

  String get displayText {
    if (address != null && address!.isNotEmpty) {
      return address!;
    }
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }
}

@JsonSerializable()
class ChatParticipant {
  final String id;
  final String userId;
  final String name;
  final String role;
  final bool isOnline;
  final DateTime joinedAt;
  final DateTime? lastSeen;

  ChatParticipant({
    required this.id,
    required this.userId,
    required this.name,
    required this.role,
    required this.isOnline,
    required this.joinedAt,
    this.lastSeen,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) =>
      _$ChatParticipantFromJson(json);
  Map<String, dynamic> toJson() => _$ChatParticipantToJson(this);

  bool get isAdmin => role == 'admin';
  bool get isModerator => role == 'moderator';

  String get statusText {
    if (isOnline) return 'Online';
    if (lastSeen != null) {
      final diff = DateTime.now().difference(lastSeen!);
      if (diff.inMinutes < 5) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    }
    return 'Offline';
  }
}

@JsonSerializable()
class CreateChatRoomRequest {
  final String name;
  final String roomType;
  final List<String> participantIds;
  final String? description;
  final Map<String, dynamic> settings;

  CreateChatRoomRequest({
    required this.name,
    required this.roomType,
    required this.participantIds,
    this.description,
    this.settings = const {},
  });

  factory CreateChatRoomRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateChatRoomRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateChatRoomRequestToJson(this);
}

@JsonSerializable()
class SendMessageRequest {
  final String messageText;
  final String messageType;
  final List<String> mediaUrls;
  final LocationData? locationData;
  final String? replyToMessageId;
  final Map<String, dynamic> metadata;

  SendMessageRequest({
    required this.messageText,
    this.messageType = 'text',
    this.mediaUrls = const [],
    this.locationData,
    this.replyToMessageId,
    this.metadata = const {},
  });

  factory SendMessageRequest.fromJson(Map<String, dynamic> json) =>
      _$SendMessageRequestFromJson(json);
  Map<String, dynamic> toJson() => _$SendMessageRequestToJson(this);
}

@JsonSerializable()
class WebSocketMessage {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  WebSocketMessage({
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) =>
      _$WebSocketMessageFromJson(json);
  Map<String, dynamic> toJson() => _$WebSocketMessageToJson(this);

  bool get isMessageReceived => type == 'message_received';
  bool get isEmergencyAlert => type == 'emergency_alert';
  bool get isUserConnected => type == 'user_connected';
  bool get isUserDisconnected => type == 'user_disconnected';
  bool get isTyping => type == 'typing';
  bool get isError => type == 'error';
}
