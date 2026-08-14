import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'biometric_service.dart';

part 'biometric_providers.g.dart';

@Riverpod(keepAlive: true)
BiometricService biometricService(Ref ref) => BiometricService();
