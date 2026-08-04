import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/cards/sa_contact_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../contacts/domain/models/contact.dart';
import 'widgets/add_contact_sheet.dart';

/// Manage emergency contacts: reorder by drag (priority), add, and
/// swipe-to-remove.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  Future<void> _handleAdd(BuildContext context, WidgetRef ref) async {
    final result = await showSaBottomSheet<(String, String)>(context, builder: (context) => const AddContactSheet());
    if (result == null) return;
    await ref.read(contactsNotifierProvider.notifier).addContact(result.$1, result.$2);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsNotifierProvider);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space2, AppSpacing.screenMarginPhone, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      'Emergency Contacts',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.plus),
                    onPressed: () => _handleAdd(context, ref),
                    tooltip: 'Add contact',
                  ),
                ],
              ),
            ),
            Expanded(
              child: contactsAsync.when(
                data: (contacts) => _ContactsList(contacts: contacts),
                loading: () => const _ContactsLoading(),
                error: (error, stackTrace) => SaEmptyState(
                  title: "Couldn't load your contacts",
                  body: 'Check your connection and try again.',
                  ctaLabel: 'Retry',
                  onCtaTap: () => ref.invalidate(contactsNotifierProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactsList extends ConsumerWidget {
  const _ContactsList({required this.contacts});

  final List<Contact> contacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (contacts.isEmpty) {
      return const SaEmptyState(
        title: 'No emergency contacts yet',
        body: 'Add someone who should be notified when you send an alert.',
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space2,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      itemCount: contacts.length,
      onReorder: (oldIndex, newIndex) {
        final reordered = List<Contact>.of(contacts);
        if (newIndex > oldIndex) newIndex -= 1;
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        ref.read(contactsNotifierProvider.notifier).reorder(reordered);
      },
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return Padding(
          key: ValueKey(contact.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.space3),
          child: Dismissible(
            key: ValueKey('dismiss-${contact.id}'),
            direction: DismissDirection.endToStart,
            background: _DeleteBackground(),
            onDismissed: (_) => ref.read(contactsNotifierProvider.notifier).removeContact(contact.id),
            child: SaContactCard(
              name: contact.name,
              relationship: contact.relationship,
              priority: index + 1,
              confirmed: contact.confirmed,
              dragHandle: const SaIcon(SaIconGlyph.refresh, size: 18),
            ),
          ),
        );
      },
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      decoration: BoxDecoration(color: saColors.threatDanger, borderRadius: AppRadius.lgRadius),
      child: const SaIcon(SaIconGlyph.close, color: Colors.white),
    );
  }
}

class _ContactsLoading extends StatelessWidget {
  const _ContactsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space3),
            child: SaLoadingShimmer(
              child: Container(height: 76, decoration: BoxDecoration(borderRadius: AppRadius.lgRadius, color: Colors.white)),
            ),
          ),
      ],
    );
  }
}
