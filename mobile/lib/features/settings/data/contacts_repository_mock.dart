import '../domain/contacts_repository.dart';
import '../domain/models/managed_contact.dart';

class ContactsRepositoryMock implements ContactsRepository {
  final List<ManagedContact> _contacts = [
    const ManagedContact(id: '1', name: 'Anika Sharma', relationship: 'Sister', confirmed: true),
    const ManagedContact(id: '2', name: 'Rahul Verma', relationship: 'Partner', confirmed: true),
    const ManagedContact(id: '3', name: 'Meera Iyer', relationship: 'Friend', confirmed: false),
  ];
  var _nextId = 4;

  @override
  Future<List<ManagedContact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<ManagedContact>> addContact(String name, String relationship) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _contacts.add(ManagedContact(id: '${_nextId++}', name: name, relationship: relationship, confirmed: false));
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<ManagedContact>> removeContact(String id) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _contacts.removeWhere((c) => c.id == id);
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<ManagedContact>> reorderContacts(List<ManagedContact> newOrder) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _contacts
      ..clear()
      ..addAll(newOrder);
    return List.unmodifiable(_contacts);
  }
}
