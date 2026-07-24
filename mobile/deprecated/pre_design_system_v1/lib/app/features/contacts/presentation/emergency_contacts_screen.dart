import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class EmergencyContactsScreenV2 extends ConsumerWidget {
  const EmergencyContactsScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final notifier = ref.read(safetyControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        actions: [
          IconButton(
            onPressed: () => _showEditor(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: SwitchListTile(
              value: safety.guardianMode,
              onChanged: notifier.setGuardianMode,
              title: const Text('Guardian Mode'),
              subtitle: const Text(
                'Prioritize guardian notifications and tracking',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final demoContact = EmergencyContactModel(
                    id: const Uuid().v4(),
                    name: 'Imported Contact',
                    phone: '+10000000000',
                    relationship: 'Friend',
                    priority: 4,
                  );
                  await notifier.addContact(demoContact);
                },
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Import from phone'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (safety.contacts.isEmpty)
            const GlassCard(child: Text('No emergency contacts added yet.'))
          else
            ...safety.contacts.map(
              (contact) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Chip(label: Text('P${contact.priority}')),
                          if (contact.isGuardian)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Chip(label: Text('Guardian')),
                            ),
                        ],
                      ),
                      Text('${contact.relationship} • ${contact.phone}'),
                      if (contact.email != null) Text(contact.email!),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _call(contact.phone),
                            icon: const Icon(Icons.call_outlined),
                            label: const Text('Call'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _sms(contact.phone),
                            icon: const Icon(Icons.sms_outlined),
                            label: const Text('Message'),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () =>
                                _showEditor(context, ref, existing: contact),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            onPressed: () => notifier.removeContact(contact.id),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

  Future<void> _sms(String phone) async {
    final uri = Uri.parse('sms:$phone');
    await launchUrl(uri);
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref, {
    EmergencyContactModel? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final relationshipCtrl = TextEditingController(
      text: existing?.relationship ?? 'Friend',
    );
    final priorityCtrl = TextEditingController(
      text: (existing?.priority ?? 5).toString(),
    );
    bool guardian = existing?.isGuardian ?? false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(existing == null ? 'Add Contact' : 'Edit Contact'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                      ),
                    ),
                    TextField(
                      controller: relationshipCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Relationship',
                      ),
                    ),
                    TextField(
                      controller: priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Priority (1-10)',
                      ),
                    ),
                    SwitchListTile(
                      value: guardian,
                      onChanged: (value) =>
                          setStateDialog(() => guardian = value),
                      title: const Text('Set as guardian'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final contact = EmergencyContactModel(
                      id: existing?.id ?? const Uuid().v4(),
                      name: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      email: emailCtrl.text.trim().isEmpty
                          ? null
                          : emailCtrl.text.trim(),
                      relationship: relationshipCtrl.text.trim(),
                      priority:
                          int.tryParse(
                            priorityCtrl.text.trim(),
                          )?.clamp(1, 10) ??
                          5,
                      isGuardian: guardian,
                    );

                    final notifier = ref.read(
                      safetyControllerProvider.notifier,
                    );
                    if (existing == null) {
                      await notifier.addContact(contact);
                    } else {
                      await notifier.updateContact(contact);
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(existing == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    relationshipCtrl.dispose();
    priorityCtrl.dispose();
  }
}
