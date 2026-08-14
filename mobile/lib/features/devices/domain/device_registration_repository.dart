import 'models/device_detail.dart';
import 'models/registered_device.dart';

/// Registers a physically-paired device with the backend.
///
/// Split out from [DeviceRepository] (which only reads the already-paired
/// list) because registration is a write against a different backend — the
/// FastAPI service in `fastapi_app/`, not Firestore.
///
/// Note: `fastapi_app/routers/devices.py` exposes `POST /register`,
/// `GET /me` and `POST /{id}/heartbeat` only. **There is no unpair /
/// delete / deactivate endpoint**, which is why there is no
/// `unregisterDevice` here — disconnecting is purely local until the
/// backend grows one. Inventing a call for it would be worse than the gap.
abstract class DeviceRegistrationRepository {
  Future<RegisteredDevice> registerDevice({
    required String deviceName,
    required DeviceType deviceType,
  });
}
