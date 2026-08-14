import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/device_registration_repository.dart';
import '../domain/models/device_detail.dart';
import '../domain/models/registered_device.dart';

/// Registers a paired device against the FastAPI backend
/// (`fastapi_app/routers/devices.py`).
///
/// This is the first repository in the app to use the shared [ApiClient];
/// the other `*RepositoryRemote` classes read from Firestore. It follows
/// [ApiClient]'s documented contract: catch [DioException] at the call
/// site and rethrow [ApiException], so callers never see Dio.
class DeviceRegistrationRepositoryRemote implements DeviceRegistrationRepository {
  const DeviceRegistrationRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// `AppConfig.apiBaseUrl` already includes the `/api/v1` prefix (see
  /// its doc comment), matching every other `*RepositoryRemote` in this
  /// app — none of them repeat that prefix in their own paths either.
  static const _registerPath = '/devices/register';

  @override
  Future<RegisteredDevice> registerDevice({
    required String deviceName,
    required DeviceType deviceType,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        _registerPath,
        data: {'device_name': deviceName, 'device_type': deviceType.name},
      );
      final data = response.data;
      if (data == null) {
        throw const ApiException(message: 'The server registered no device. Please try again.');
      }
      return RegisteredDevice.fromJson(data);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}
