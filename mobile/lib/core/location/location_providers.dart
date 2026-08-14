import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'location_service.dart';

part 'location_providers.g.dart';

@Riverpod(keepAlive: true)
LocationService locationService(Ref ref) => LocationService();
