// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  chatRoomId: json['chatRoomId'] as String,
  senderId: json['senderId'] as String,
  senderName: json['senderName'] as String,
  content: json['content'] as String,
  messageType: json['messageType'] as String,
  timestamp: DateTime.parse(json['timestamp'] as String),
  isRead: json['isRead'] as bool? ?? false,
  metadata: json['metadata'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'chatRoomId': instance.chatRoomId,
  'senderId': instance.senderId,
  'senderName': instance.senderName,
  'content': instance.content,
  'messageType': instance.messageType,
  'timestamp': instance.timestamp.toIso8601String(),
  'isRead': instance.isRead,
  'metadata': instance.metadata,
};
