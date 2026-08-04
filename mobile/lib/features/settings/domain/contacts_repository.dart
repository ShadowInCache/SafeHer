import 'models/managed_contact.dart';

abstract class ContactsRepository {
  Future<List<ManagedContact>> getContacts();
  Future<List<ManagedContact>> addContact(String name, String relationship);
  Future<List<ManagedContact>> removeContact(String id);
  Future<List<ManagedContact>> reorderContacts(List<ManagedContact> newOrder);
}
