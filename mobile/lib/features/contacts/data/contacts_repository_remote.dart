import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/contacts_repository.dart';
import '../domain/models/contact.dart';

/// Firestore-backed [ContactsRepository]. Contacts live at
/// `users/{uid}/contacts/{contactId}`; [priority] is kept in sync with
/// list order on every mutation, same as the mock implementation.
class ContactsRepositoryRemote implements ContactsRepository {
  ContactsRepositoryRemote({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _collection {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return _firestore.collection('users').doc(uid).collection('contacts');
  }

  Contact _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Contact(
      id: doc.id,
      name: data['name'] as String,
      relationship: data['relationship'] as String,
      priority: data['priority'] as int,
      confirmed: data['confirmed'] as bool? ?? false,
    );
  }

  @override
  Future<List<Contact>> getContacts() async {
    final snapshot = await _collection.orderBy('priority').get();
    return snapshot.docs.map(_fromDoc).toList();
  }

  @override
  Future<List<Contact>> addContact(String name, String relationship) async {
    final existing = await getContacts();
    await _collection.add({
      'name': name,
      'relationship': relationship,
      'priority': existing.length + 1,
      'confirmed': false,
    });
    return getContacts();
  }

  @override
  Future<List<Contact>> removeContact(String id) async {
    await _collection.doc(id).delete();
    return reorderContacts(await getContacts());
  }

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) async {
    final batch = _firestore.batch();
    for (var i = 0; i < newOrder.length; i++) {
      batch.update(_collection.doc(newOrder[i].id), {'priority': i + 1});
    }
    await batch.commit();
    return getContacts();
  }
}
