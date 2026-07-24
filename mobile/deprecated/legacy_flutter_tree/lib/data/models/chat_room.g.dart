// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_room.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatRoom _$ChatRoomFromJson(Map<String, dynamic> json) => ChatRoom(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  roomType: json['roomType'] as String,
  creatorId: json['creatorId'] as String,
  isActive: json['isActive'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  participantCount: (json['participantCount'] as num).toInt(),
  unreadCount: (json['unreadCount'] as num).toInt(),
  userRole: json['userRole'] as String?,
  latestMessage: json['latestMessage'] == null
      ? null
      : Message.fromJson(json['latestMessage'] as Map<String, dynamic>),
  isMuted: json['isMuted'] as bool,
  settings: json['settings'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$ChatRoomToJson(ChatRoom instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'roomType': instance.roomType,
  'creatorId': instance.creatorId,
  'isActive': instance.isActive,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'participantCount': instance.participantCount,
  'unreadCount': instance.unreadCount,
  'userRole': instance.userRole,
  'latestMessage': instance.latestMessage,
  'isMuted': instance.isMuted,
  'settings': instance.settings,
};

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  senderId: json['senderId'] as String,
  messageType: json['messageType'] as String,
  content: MessageContent.fromJson(json['content'] as Map<String, dynamic>),
  status: json['status'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  replyToMessageId: json['replyToMessageId'] as String?,
  location: json['location'] == null
      ? null
      : LocationData.fromJson(json['location'] as Map<String, dynamic>),
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'senderId': instance.senderId,
  'messageType': instance.messageType,
  'content': instance.content,
  'status': instance.status,
  'createdAt': instance.createdAt.toIso8601String(),
  'replyToMessageId': instance.replyToMessageId,
  'location': instance.location,
};

MessageContent _$MessageContentFromJson(Map<String, dynamic> json) =>
    MessageContent(
      text: json['text'] as String,
      mediaUrls:
          (json['mediaUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$MessageContentToJson(MessageContent instance) =>
    <String, dynamic>{
      'text': instance.text,
      'mediaUrls': instance.mediaUrls,
      'metadata': instance.metadata,
    };

LocationData _$LocationDataFromJson(Map<String, dynamic> json) => LocationData(
  latitude: (json['latitude'] as num).toDouble(),
  longitude: (json['longitude'] as num).toDouble(),
  accuracy: (json['accuracy'] as num?)?.toDouble(),
  address: json['address'] as String?,
);

Map<String, dynamic> _$LocationDataToJson(LocationData instance) =>
    <String, dynamic>{
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'accuracy': instance.accuracy,
      'address': instance.address,
    };

ChatParticipant _$ChatParticipantFromJson(Map<String, dynamic> json) =>
    ChatParticipant(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      isOnline: json['isOnline'] as bool,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      lastSeen: json['lastSeen'] == null
          ? null
          : DateTime.parse(json['lastSeen'] as String),
    );

Map<String, dynamic> _$ChatParticipantToJson(ChatParticipant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'name': instance.name,
      'role': instance.role,
      'isOnline': instance.isOnline,
      'joinedAt': instance.joinedAt.toIso8601String(),
      'lastSeen': instance.lastSeen?.toIso8601String(),
    };

CreateChatRoomRequest _$CreateChatRoomRequestFromJson(
  Map<String, dynamic> json,
) => CreateChatRoomRequest(
  name: json['name'] as String,
  roomType: json['roomType'] as String,
  participantIds: (json['participantIds'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  description: json['description'] as String?,
  settings: json['settings'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$CreateChatRoomRequestToJson(
  CreateChatRoomRequest instance,
) => <String, dynamic>{
  'name': instance.name,
  'roomType': instance.roomType,
  'participantIds': instance.participantIds,
  'description': instance.description,
  'settings': instance.settings,
};

SendMessageRequest _$SendMessageRequestFromJson(Map<String, dynamic> json) =>
    SendMessageRequest(
      messageText: json['messageText'] as String,
      messageType: json['messageType'] as String? ?? 'text',
      mediaUrls:
          (json['mediaUrls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      locationData: json['locationData'] == null
          ? null
          : LocationData.fromJson(json['locationData'] as Map<String, dynamic>),
      replyToMessageId: json['replyToMessageId'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$SendMessageRequestToJson(SendMessageRequest instance) =>
    <String, dynamic>{
      'messageText': instance.messageText,
      'messageType': instance.messageType,
      'mediaUrls': instance.mediaUrls,
      'locationData': instance.locationData,
      'replyToMessageId': instance.replyToMessageId,
      'metadata': instance.metadata,
    };

WebSocketMessage _$WebSocketMessageFromJson(Map<String, dynamic> json) =>
    WebSocketMessage(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>,
      timestamp: json['timestamp'] == null
          ? null
          : DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$WebSocketMessageToJson(WebSocketMessage instance) =>
    <String, dynamic>{
      'type': instance.type,
      'data': instance.data,
      'timestamp': instance.timestamp.toIso8601String(),
    };
