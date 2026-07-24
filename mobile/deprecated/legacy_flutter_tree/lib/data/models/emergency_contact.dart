import 'package:json_annotation/json_annotation.dart';

part 'emergency_contact.g.dart';

@JsonSerializable()
class EmergencyContact {
  @JsonKey(name: 'contact_id')
  final String contactId;

  @JsonKey(name: 'user_id')
  final String userId;

  final String name;

  @JsonKey(name: 'phone_number')
  final String phoneNumber;

  final String? email;

  final String relationship;

  final int priority; // 1 = highest priority

  @JsonKey(name: 'created_at')
  final String? createdAt;

  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  EmergencyContact({
    required this.contactId,
    required this.userId,
    required this.name,
    required this.phoneNumber,
    this.email,
    required this.relationship,
    required this.priority,
    this.createdAt,
    this.updatedAt,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      _$EmergencyContactFromJson(json);

  Map<String, dynamic> toJson() => _$EmergencyContactToJson(this);

  EmergencyContact copyWith({
    String? contactId,
    String? userId,
    String? name,
    String? phoneNumber,
    String? email,
    String? relationship,
    int? priority,
    String? createdAt,
    String? updatedAt,
  }) {
    return EmergencyContact(
      contactId: contactId ?? this.contactId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      relationship: relationship ?? this.relationship,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'EmergencyContact(contactId: $contactId, name: $name, phoneNumber: $phoneNumber, relationship: $relationship, priority: $priority)';
  }
}
