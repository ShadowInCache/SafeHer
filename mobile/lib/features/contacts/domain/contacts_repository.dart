import 'models/contact.dart';

abstract class ContactsRepository {
  Future<List<Contact>> getContacts();
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  });
  Future<List<Contact>> removeContact(String id);
  Future<List<Contact>> reorderContacts(List<Contact> newOrder);
}
