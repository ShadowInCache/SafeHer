import '../domain/device_registration_repository.dart';
import '../domain/models/device_detail.dart';
import '../domain/models/registered_device.dart';

/// Stand-in used only while `AppConfig.useMockApi` is true (its default,
/// because no SafeHer backend is deployed yet) — the same arrangement
/// every other feature uses for its `*RepositoryRemote`.
///
/// It invents no device: the name and type it echoes back are the ones
/// from the peripheral you genuinely connected to, with a local id in
/// place of the backend's. Flip `USE_MOCK_API=false` and the real
/// `POST /api/v1/devices/register` call takes over unchanged.
class DeviceRegistrationRepositoryMock implements DeviceRegistrationRepository {
  @override
  Future<RegisteredDevice> registerDevice({
    required String deviceName,
    required DeviceType deviceType,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return RegisteredDevice(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      deviceName: deviceName,
      deviceType: deviceType,
      isActive: true,
    );
  }
}
