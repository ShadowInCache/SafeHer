import '../domain/contacts_repository.dart';
import '../domain/models/contact.dart';

/// Single in-memory contacts list shared by every feature that reads or
/// manages contacts. [priority] always reflects list order (1-based) —
/// callers don't set it directly, it's recomputed on every mutation.
class ContactsRepositoryMock implements ContactsRepository {
  final List<Contact> _contacts = [
    const Contact(id: '1', name: 'Anika Sharma', phone: '+15550101001', relationship: 'Sister', priority: 1, confirmed: true),
    const Contact(id: '2', name: 'Rahul Verma', phone: '+15550101002', relationship: 'Partner', priority: 2, confirmed: true),
    const Contact(id: '3', name: 'Meera Iyer', phone: '+15550101003', relationship: 'Friend', priority: 3, confirmed: false),
  ];
  var _nextId = 4;

  List<Contact> _withPriorities(List<Contact> contacts) => [
    for (var i = 0; i < contacts.length; i++)
      Contact(
        id: contacts[i].id,
        name: contacts[i].name,
        phone: contacts[i].phone,
        relationship: contacts[i].relationship,
        priority: i + 1,
        confirmed: contacts[i].confirmed,
      ),
  ];

  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _contacts.add(
      Contact(
        id: '${_nextId++}',
        name: name,
        phone: phone,
        relationship: relationship,
        priority: 0,
        confirmed: false,
        email: email,
      ),
    );
    final updated = _withPriorities(_contacts);
    _contacts
      ..clear()
      ..addAll(updated);
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> removeContact(String id) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _contacts.removeWhere((c) => c.id == id);
    final updated = _withPriorities(_contacts);
    _contacts
      ..clear()
      ..addAll(updated);
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _contacts
      ..clear()
      ..addAll(_withPriorities(newOrder));
    return List.unmodifiable(_contacts);
  }
}
