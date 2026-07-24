import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/safety/data/safety_repository.dart';
import '../models/domain_models.dart';

class SafetyContactsState {
  final List<EmergencyContactModel> contacts;
  final List<NotificationRecordModel> notifications;

  const SafetyContactsState({
    required this.contacts,
    required this.notifications,
  });

  factory SafetyContactsState.initial() {
    return const SafetyContactsState(contacts: [], notifications: []);
  }

  SafetyContactsState copyWith({
    List<EmergencyContactModel>? contacts,
    List<NotificationRecordModel>? notifications,
  }) {
    return SafetyContactsState(
      contacts: contacts ?? this.contacts,
      notifications: notifications ?? this.notifications,
    );
  }
}

class SafetyContactsNotifier extends StateNotifier<SafetyContactsState> {
  final SafetyRepository _safetyRepository;

  SafetyContactsNotifier({required SafetyRepository safetyRepository})
    : _safetyRepository = safetyRepository,
      super(SafetyContactsState.initial());

  Future<void> initialize() async {
    final contacts = await _safetyRepository.loadContacts();
    final notifications = await _safetyRepository.loadNotifications();
    state = state.copyWith(contacts: contacts, notifications: notifications);
  }

  Future<void> addContact(EmergencyContactModel contact) async {
    final updated = [...state.contacts, contact]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    await _safetyRepository.saveContact(contact);
    state = state.copyWith(contacts: updated);
  }

  Future<void> updateContact(EmergencyContactModel contact) async {
    await _safetyRepository.saveContact(contact);
    final updated =
        state.contacts
            .map((item) => item.id == contact.id ? contact : item)
            .toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
    state = state.copyWith(contacts: updated);
  }

  Future<void> removeContact(String contactId) async {
    await _safetyRepository.deleteContact(contactId);
    state = state.copyWith(
      contacts: state.contacts.where((item) => item.id != contactId).toList(),
    );
  }

  Future<void> markNotificationRead(String id) async {
    final updated = state.notifications
        .map((item) => item.id == id ? item.copyWith(read: true) : item)
        .toList();

    for (final notification in updated) {
      await _safetyRepository.saveNotification(notification);
    }

    state = state.copyWith(notifications: updated);
  }

  void appendNotification(NotificationRecordModel notification) {
    state = state.copyWith(
      notifications: [notification, ...state.notifications],
    );
  }
}
