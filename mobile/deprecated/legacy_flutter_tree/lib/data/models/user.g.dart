// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: json['id'] as String,
  email: json['email'] as String,
  name: json['name'] as String,
  phoneNumber: json['phoneNumber'] as String?,
  role: json['role'] as String,
  isActive: json['isActive'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  profile: json['profile'] == null
      ? null
      : UserProfile.fromJson(json['profile'] as Map<String, dynamic>),
  emergencyContacts:
      (json['emergencyContacts'] as List<dynamic>?)
          ?.map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  devices:
      (json['devices'] as List<dynamic>?)
          ?.map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'email': instance.email,
  'name': instance.name,
  'phoneNumber': instance.phoneNumber,
  'role': instance.role,
  'isActive': instance.isActive,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'profile': instance.profile,
  'emergencyContacts': instance.emergencyContacts,
  'devices': instance.devices,
};

UserProfile _$UserProfileFromJson(Map<String, dynamic> json) => UserProfile(
  fullName: json['fullName'] as String?,
  dateOfBirth: json['dateOfBirth'] == null
      ? null
      : DateTime.parse(json['dateOfBirth'] as String),
  address: json['address'] as String?,
  city: json['city'] as String?,
  country: json['country'] as String?,
  emergencyMedicalInfo: json['emergencyMedicalInfo'] as String?,
  preferences: json['preferences'] as Map<String, dynamic>? ?? const {},
  privacySettings: json['privacySettings'] as Map<String, dynamic>? ?? const {},
);

Map<String, dynamic> _$UserProfileToJson(UserProfile instance) =>
    <String, dynamic>{
      'fullName': instance.fullName,
      'dateOfBirth': instance.dateOfBirth?.toIso8601String(),
      'address': instance.address,
      'city': instance.city,
      'country': instance.country,
      'emergencyMedicalInfo': instance.emergencyMedicalInfo,
      'preferences': instance.preferences,
      'privacySettings': instance.privacySettings,
    };

EmergencyContact _$EmergencyContactFromJson(Map<String, dynamic> json) =>
    EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      phoneNumber: json['phoneNumber'] as String,
      email: json['email'] as String?,
      relationship: json['relationship'] as String,
      isPrimary: json['isPrimary'] as bool,
      isActive: json['isActive'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$EmergencyContactToJson(EmergencyContact instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'phoneNumber': instance.phoneNumber,
      'email': instance.email,
      'relationship': instance.relationship,
      'isPrimary': instance.isPrimary,
      'isActive': instance.isActive,
      'createdAt': instance.createdAt.toIso8601String(),
    };

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['id'] as String,
  deviceId: json['deviceId'] as String,
  deviceType: json['deviceType'] as String,
  platform: json['platform'] as String,
  appVersion: json['appVersion'] as String,
  pushToken: json['pushToken'] as String?,
  isActive: json['isActive'] as bool,
  lastSeen: DateTime.parse(json['lastSeen'] as String),
  registeredAt: DateTime.parse(json['registeredAt'] as String),
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'deviceId': instance.deviceId,
  'deviceType': instance.deviceType,
  'platform': instance.platform,
  'appVersion': instance.appVersion,
  'pushToken': instance.pushToken,
  'isActive': instance.isActive,
  'lastSeen': instance.lastSeen.toIso8601String(),
  'registeredAt': instance.registeredAt.toIso8601String(),
};

AuthResponse _$AuthResponseFromJson(Map<String, dynamic> json) => AuthResponse(
  accessToken: json['accessToken'] as String,
  tokenType: json['tokenType'] as String,
  expiresIn: (json['expiresIn'] as num).toInt(),
  refreshToken: json['refreshToken'] as String?,
  user: User.fromJson(json['user'] as Map<String, dynamic>),
);

Map<String, dynamic> _$AuthResponseToJson(AuthResponse instance) =>
    <String, dynamic>{
      'accessToken': instance.accessToken,
      'tokenType': instance.tokenType,
      'expiresIn': instance.expiresIn,
      'refreshToken': instance.refreshToken,
      'user': instance.user,
    };
