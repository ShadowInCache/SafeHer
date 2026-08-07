import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/device_repository.dart';
import '../domain/models/device_detail.dart';

/// Firestore-backed [DeviceRepository]. Devices live at
/// `users/{uid}/devices/{deviceId}` — pairing a physical device (BLE flow)
/// writes here; this just reads what's already been paired.
class DeviceRepositoryRemote implements DeviceRepository {
  DeviceRepositoryRemote({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return _firestore.collection('users').doc(uid).collection('devices');
  }

  DeviceDetail _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final sensors = data['sensors'] as Map<String, dynamic>? ?? const {};
    return DeviceDetail(
      id: doc.id,
      name: data['name'] as String,
      type: DeviceType.values.byName(data['type'] as String? ?? 'ring'),
      isOnline: data['isOnline'] as bool? ?? false,
      batteryPercent: (data['batteryPercent'] as num?)?.toDouble() ?? 0,
      batteryHoursRemaining: (data['batteryHoursRemaining'] as num?)?.toInt() ?? 0,
      signalStrength: (data['signalStrength'] as num?)?.toInt() ?? 0,
      firmwareVersion: data['firmwareVersion'] as String? ?? 'unknown',
      updateAvailable: data['updateAvailable'] as bool? ?? false,
      sensors: SensorReading(
        accelG: (sensors['accelG'] as num?)?.toDouble() ?? 0,
        gyroDps: (sensors['gyroDps'] as num?)?.toDouble() ?? 0,
        flexPercent: (sensors['flexPercent'] as num?)?.toDouble() ?? 0,
      ),
    );
  }

  @override
  Future<List<DeviceDetail>> getDevices() async {
    final snapshot = await _collection.get();
    return snapshot.docs.map(_fromDoc).toList();
  }
}
