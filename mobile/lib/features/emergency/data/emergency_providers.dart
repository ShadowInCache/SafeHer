import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/emergency_repository.dart';
import '../domain/models/emergency_contact_summary.dart';
import 'emergency_repository_mock.dart';

part 'emergency_providers.g.dart';

@riverpod
EmergencyRepository emergencyRepository(Ref ref) {
  return EmergencyRepositoryMock();
}

@riverpod
Future<List<EmergencyContactSummary>> emergencyContacts(Ref ref) async {
  return ref.watch(emergencyRepositoryProvider).getEmergencyContacts();
}
