import 'models/alert_channels.dart';
import 'models/contact.dart';

abstract class ContactsRepository {
  Future<List<Contact>> getContacts();

  /// Which emergency channels the server can deliver on.
  Future<AlertChannels> getAlertChannels();
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  });
  /// Edits an existing contact. Only non-null fields are sent, so a caller
  /// can add a missing email without having to restate the rest.
  ///
  /// This exists because a contact saved with only a phone number is
  /// unreachable while SMS is unconfigured, and until now there was no way
  /// to add an address after the fact — the only remedy was deleting the
  /// contact and typing it again.
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  });

  Future<List<Contact>> removeContact(String id);
  Future<List<Contact>> reorderContacts(List<Contact> newOrder);
}
