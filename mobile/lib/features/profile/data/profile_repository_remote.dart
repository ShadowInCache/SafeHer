import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';

/// `fastapi_app`-backed [ProfileRepository] — `GET`/`PATCH /api/v1/users/me`.
/// `safetyScore`/`streakDays` stay null: there is no backend concept of
/// either today (see [UserProfile]'s doc comment).
class ProfileRepositoryRemote implements ProfileRepository {
  ProfileRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  UserProfile _fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] as String?;
    final createdAt = createdAtRaw != null ? DateTime.tryParse(createdAtRaw) : null;
    return UserProfile(
      name: (json['full_name'] as String?) ?? 'SafeHer User',
      email: json['email'] as String? ?? '',
      phone: (json['phone'] as String?) ?? '',
      memberSince: createdAt != null ? _formatMonthYear(createdAt) : '—',
      safetyScore: null,
      streakDays: null,
    );
  }

  @override
  Future<List<int>> exportMyData() async {
    // Asked for as bytes so the document reaches the file exactly as the
    // server wrote it — Dio would otherwise decode the JSON and the caller
    // would re-encode it, changing key order and formatting in a document
    // whose whole purpose is to be a faithful copy.
    final response = await _apiClient.dio.get<List<int>>(
      '/users/me/export',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }

  @override
  Future<UserProfile> getUserProfile() async {
    final response = await _apiClient.dio.get('/users/me');
    return _fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<UserProfile> updateProfile({
    String? name,
    String? phone,
    double? threatThreshold,
  }) async {
    final response = await _apiClient.dio.patch(
      '/users/me',
      data: {
        if (name != null) 'full_name': name,
        if (phone != null) 'phone': phone,
        if (threatThreshold != null) 'threat_threshold': threatThreshold,
      },
    );
    return _fromJson(response.data as Map<String, dynamic>);
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _formatMonthYear(DateTime dt) => '${_months[dt.month - 1]} ${dt.year}';
}
