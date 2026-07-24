// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emergency_contact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmergencyContact _$EmergencyContactFromJson(Map<String, dynamic> json) =>
    EmergencyContact(
      contactId: json['contact_id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phone_number'] as String,
      email: json['email'] as String?,
      relationship: json['relationship'] as String,
      priority: json['priority'] as int,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );

Map<String, dynamic> _$EmergencyContactToJson(EmergencyContact instance) =>
    <String, dynamic>{
      'contact_id': instance.contactId,
      'user_id': instance.userId,
      'name': instance.name,
      'phone_number': instance.phoneNumber,
      'email': instance.email,
      'relationship': instance.relationship,
      'priority': instance.priority,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };
