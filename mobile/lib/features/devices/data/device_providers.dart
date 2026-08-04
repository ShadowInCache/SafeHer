import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/device_repository.dart';
import '../domain/models/device_detail.dart';
import 'device_repository_mock.dart';

part 'device_providers.g.dart';

@riverpod
DeviceRepository deviceRepository(Ref ref) {
  return DeviceRepositoryMock();
}

@riverpod
Future<List<DeviceDetail>> devices(Ref ref) async {
  return ref.watch(deviceRepositoryProvider).getDevices();
}
