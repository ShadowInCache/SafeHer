import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../domain/device_repository.dart';
import '../domain/models/device_detail.dart';
import 'device_repository_mock.dart';
import 'device_repository_remote.dart';

part 'device_providers.g.dart';

@riverpod
DeviceRepository deviceRepository(Ref ref) {
  if (AppConfig.useMockApi) return DeviceRepositoryMock();
  return DeviceRepositoryRemote();
}

@riverpod
Future<List<DeviceDetail>> devices(Ref ref) async {
  return ref.watch(deviceRepositoryProvider).getDevices();
}
