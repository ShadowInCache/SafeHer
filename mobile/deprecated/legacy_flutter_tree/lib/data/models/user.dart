import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final String id;
  final String email;
  final String name;
  final String? phoneNumber;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final UserProfile? profile;
  final List<EmergencyContact> emergencyContacts;
  final List<Device> devices;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.phoneNumber,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.profile,
    this.emergencyContacts = const [],
    this.devices = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? phoneNumber,
    String? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    UserProfile? profile,
    List<EmergencyContact>? emergencyContacts,
    List<Device>? devices,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profile: profile ?? this.profile,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      devices: devices ?? this.devices,
    );
  }
}

@JsonSerializable()
class UserProfile {
  final String? fullName;
  final DateTime? dateOfBirth;
  final String? address;
  final String? city;
  final String? country;
  final String? emergencyMedicalInfo;
  final Map<String, dynamic> preferences;
  final Map<String, dynamic> privacySettings;

  UserProfile({
    this.fullName,
    this.dateOfBirth,
    this.address,
    this.city,
    this.country,
    this.emergencyMedicalInfo,
    this.preferences = const {},
    this.privacySettings = const {},
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
  Map<String, dynamic> toJson() => _$UserProfileToJson(this);
}

@JsonSerializable()
class EmergencyContact {
  final String id;
  final String name;
  final String phoneNumber;
  final String? email;
  final String relationship;
  final bool isPrimary;
  final bool isActive;
  final DateTime createdAt;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.email,
    required this.relationship,
    required this.isPrimary,
    required this.isActive,
    required this.createdAt,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      _$EmergencyContactFromJson(json);
  Map<String, dynamic> toJson() => _$EmergencyContactToJson(this);
}

@JsonSerializable()
class Device {
  final String id;
  final String deviceId;
  final String deviceType;
  final String platform;
  final String appVersion;
  final String? pushToken;
  final bool isActive;
  final DateTime lastSeen;
  final DateTime registeredAt;

  Device({
    required this.id,
    required this.deviceId,
    required this.deviceType,
    required this.platform,
    required this.appVersion,
    this.pushToken,
    required this.isActive,
    required this.lastSeen,
    required this.registeredAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceToJson(this);
}

@JsonSerializable()
class AuthResponse {
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String? refreshToken;
  final User user;

  AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);
}
