import '../../../core/network/api_client.dart';
import '../domain/contacts_repository.dart';
import '../domain/models/alert_channels.dart';
import '../domain/models/contact.dart';

/// `fastapi_app`-backed [ContactsRepository] — `/api/v1/users/me/emergency-contacts`.
/// See repo root API.md for the exact request/response shapes.
class ContactsRepositoryRemote implements ContactsRepository {
  ContactsRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _basePath = '/users/me/emergency-contacts';

  Contact _fromJson(Map<String, dynamic> json) => Contact(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String,
    // The backend has no contact-confirmation workflow (no per-contact OTP
    // invite, unlike the aspirational SRS FR-EMG-10) — a contact existing
    // on the server is the only "confirmed" state there is today.
    confirmed: true,
    relationship: json['relationship'] as String? ?? 'trusted_contact',
    priority: json['priority'] as int? ?? 1,
    email: json['email'] as String?,
  );

  @override
  Future<List<Contact>> getContacts() async {
    final response = await _apiClient.dio.get(_basePath);
    return (response.data as List).cast<Map<String, dynamic>>().map(_fromJson).toList();
  }

  @override
  Future<AlertChannels> getAlertChannels() async {
    final response = await _apiClient.dio.get('/alerts/channels');
    return AlertChannels.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) async {
    final existing = await getContacts();
    await _apiClient.dio.post(
      _basePath,
      data: {
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'priority': existing.length + 1,
        // Omitted rather than sent as null/empty: the backend validates
        // this as an EmailStr, and an empty string fails that check.
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    return getContacts();
  }

  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async {
    await _apiClient.dio.put('$_basePath/$id', data: {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (relationship != null) 'relationship': relationship,
      // Same rule as addContact: the backend validates this as an EmailStr,
      // so an empty string is a 422 rather than a way to clear the field.
      if (email != null && email.isNotEmpty) 'email': email,
    });
    return getContacts();
  }

  @override
  Future<List<Contact>> removeContact(String id) async {
    await _apiClient.dio.delete('$_basePath/$id');
    return reorderContacts(await getContacts());
  }

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) async {
    for (var i = 0; i < newOrder.length; i++) {
      final desiredPriority = i + 1;
      if (newOrder[i].priority == desiredPriority) continue;
      await _apiClient.dio.put('$_basePath/${newOrder[i].id}', data: {'priority': desiredPriority});
    }
    return getContacts();
  }
}
