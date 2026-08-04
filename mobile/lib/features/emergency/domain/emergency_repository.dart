import 'models/emergency_contact_summary.dart';

abstract class EmergencyRepository {
  Future<List<EmergencyContactSummary>> getEmergencyContacts();
}
