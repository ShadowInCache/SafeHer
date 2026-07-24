import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/emergency_contact.dart';
import '../../data/services/api_service.dart';

// Emergency contacts provider - fetches list of contacts for a user
final emergencyContactsProvider =
    FutureProvider.family<List<EmergencyContact>, String>((ref, userId) async {
      final apiService = ref.watch(apiServiceProvider);
      try {
        final response = await apiService.getUserEmergencyContacts(userId);
        final contactsList = List.from(response);
        return contactsList
            .map(
              (item) => EmergencyContact.fromJson(item as Map<String, dynamic>),
            )
            .toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
      } catch (e) {
        throw Exception('Failed to fetch emergency contacts: $e');
      }
    });

// State notifier for managing emergency contacts
class EmergencyContactNotifier extends StateNotifier<List<EmergencyContact>> {
  final ApiService apiService;
  final String userId;

  EmergencyContactNotifier({required this.apiService, required this.userId})
    : super([]);

  Future<void> loadContacts() async {
    try {
      final response = await apiService.getUserEmergencyContacts(userId);
      final contactsList = List.from(response);
      final contacts =
          contactsList
              .map(
                (item) =>
                    EmergencyContact.fromJson(item as Map<String, dynamic>),
              )
              .toList()
            ..sort((a, b) => a.priority.compareTo(b.priority));
      state = contacts;
    } catch (e) {
      throw Exception('Failed to load emergency contacts: $e');
    }
  }

  Future<void> addContact({
    required String name,
    required String phoneNumber,
    String? email,
    String relationship = 'friend',
    int priority = 1,
  }) async {
    try {
      final result = await apiService.addEmergencyContact(
        userId: userId,
        name: name,
        phoneNumber: phoneNumber,
        email: email,
        relationship: relationship,
        priority: priority,
      );

      if (result['status'] == 'success') {
        // Add to local state
        final newContact = EmergencyContact(
          contactId: result['contact_id'],
          userId: userId,
          name: name,
          phoneNumber: phoneNumber,
          email: email,
          relationship: relationship,
          priority: priority,
          createdAt: DateTime.now().toIso8601String(),
        );
        state = [...state, newContact]
          ..sort((a, b) => a.priority.compareTo(b.priority));
      } else {
        throw Exception(result['error'] ?? 'Failed to add contact');
      }
    } catch (e) {
      throw Exception('Failed to add emergency contact: $e');
    }
  }

  Future<void> updateContact({
    required String contactId,
    String? name,
    String? phoneNumber,
    String? email,
    String? relationship,
    int? priority,
  }) async {
    try {
      final result = await apiService.updateEmergencyContact(
        contactId: contactId,
        name: name,
        phoneNumber: phoneNumber,
        email: email,
        relationship: relationship,
        priority: priority,
      );

      if (result['status'] == 'success') {
        // Update in local state
        final index = state.indexWhere((c) => c.contactId == contactId);
        if (index != -1) {
          state[index] = state[index].copyWith(
            name: name ?? state[index].name,
            phoneNumber: phoneNumber ?? state[index].phoneNumber,
            email: email ?? state[index].email,
            relationship: relationship ?? state[index].relationship,
            priority: priority ?? state[index].priority,
          );
          state = [...state]..sort((a, b) => a.priority.compareTo(b.priority));
        }
      } else {
        throw Exception(result['error'] ?? 'Failed to update contact');
      }
    } catch (e) {
      throw Exception('Failed to update emergency contact: $e');
    }
  }

  Future<void> deleteContact(String contactId) async {
    try {
      final result = await apiService.deleteEmergencyContact(contactId);

      if (result['status'] == 'success') {
        // Remove from local state
        state = state.where((c) => c.contactId != contactId).toList();
      } else {
        throw Exception(result['error'] ?? 'Failed to delete contact');
      }
    } catch (e) {
      throw Exception('Failed to delete emergency contact: $e');
    }
  }
}

// State notifier provider for emergency contacts
final emergencyContactNotifierProvider =
    StateNotifierProvider<EmergencyContactNotifier, List<EmergencyContact>>((
      ref,
    ) {
      // This should be initialized with actual userId from auth provider
      return EmergencyContactNotifier(
        apiService: ref.watch(apiServiceProvider),
        userId: 'user_placeholder', // Replace with actual userId from auth
      );
    });
