import '../domain/emergency_repository.dart';
import '../domain/models/emergency_contact_summary.dart';

class EmergencyRepositoryMock implements EmergencyRepository {
  @override
  Future<List<EmergencyContactSummary>> getEmergencyContacts() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return const [
      EmergencyContactSummary(id: '1', name: 'Anika Sharma', relationship: 'Sister', priority: 1),
      EmergencyContactSummary(id: '2', name: 'Rahul Verma', relationship: 'Partner', priority: 2),
      EmergencyContactSummary(id: '3', name: 'Meera Iyer', relationship: 'Friend', priority: 3),
    ];
  }
}
