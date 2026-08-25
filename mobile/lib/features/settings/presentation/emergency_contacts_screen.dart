import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/external_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_contact_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../contacts/domain/models/alert_channels.dart';
import '../../contacts/domain/models/contact.dart';
import 'widgets/add_contact_sheet.dart';
import 'widgets/verify_contact_sheet.dart';

/// Manage emergency contacts: reorder by drag (priority), add, and
/// swipe-to-remove.
class EmergencyContactsScreen extends ConsumerWidget {
  const EmergencyContactsScreen({super.key});

  Future<void> _handleAdd(BuildContext context, WidgetRef ref) async {
    final result = await showSaBottomSheet<(String, String, String, String)>(
      context,
      builder: (context) => const AddContactSheet(),
    );
    if (result == null) return;
    final email = result.$4.trim();
    await ref
        .read(contactsNotifierProvider.notifier)
        .addContact(result.$1, result.$2, result.$3, email: email.isEmpty ? null : email);
  }

  Future<void> _handleEdit(BuildContext context, WidgetRef ref, Contact contact) async {
    final result = await showSaBottomSheet<(String, String, String, String)>(
      context,
      builder: (context) => AddContactSheet(
        initialName: contact.name,
        initialPhone: contact.phone,
        initialRelationship: contact.relationship,
        initialEmail: contact.email,
      ),
    );
    if (result == null) return;
    final email = result.$4.trim();
    await ref.read(contactsNotifierProvider.notifier).updateContact(
      contact.id,
      name: result.$1,
      phone: result.$2,
      relationship: result.$3,
      email: email.isEmpty ? null : email,
    );
  }

  Future<void> _handleVerify(BuildContext context, WidgetRef ref, Contact contact) async {
    final verified = await showSaBottomSheet<bool>(
      context,
      builder: (context) => VerifyContactSheet(contact: contact),
    );
    if (verified == true && context.mounted) {
      showSaToast(
        context,
        title: 'Contact confirmed',
        message: '${contact.name} will receive your emergency alerts.',
        type: SaToastType.success,
      );
    }
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
                data: (contacts) => _ContactsList(
                  contacts: contacts,
                  onEdit: (contact) => _handleEdit(context, ref, contact),
                  onVerify: (contact) => _handleVerify(context, ref, contact),
                ),
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
  const _ContactsList({
    required this.contacts,
    required this.onEdit,
    required this.onVerify,
  });

  final void Function(Contact contact) onEdit;
  final void Function(Contact contact) onVerify;

  final List<Contact> contacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Optimistic until the real answer arrives, so a warning never flashes
    // on screen and then retracts itself.
    final channels =
        ref.watch(alertChannelsProvider).valueOrNull ?? const AlertChannels.optimistic();

    if (contacts.isEmpty) {
      return const SaEmptyState(
        title: 'No emergency contacts yet',
        body: 'Add someone who should be notified when you send an alert.',
      );
    }

    return ReorderableListView.builder(
      // On web and desktop ReorderableListView draws its own handle at the
      // trailing edge, vertically centred over the whole item. Each item here
      // is a card plus an optional notice plus a Call/Message row, so that
      // handle landed in the middle of the notice and sat on top of the text
      // -- "this contact has no em[=]l address". The card already carries a
      // handle, so Flutter's is switched off and the card's is made the real
      // drag affordance below; long-press to reorder still works on mobile.
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space2,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      itemCount: contacts.length,
      // ignore: deprecated_member_use -- onReorderItem isn't available on
      // the Flutter SDK version pinned for local dev yet; onReorder still
      // works identically, just needs the oldIndex/newIndex adjustment below.
      onReorder: (oldIndex, newIndex) {
        final reordered = List<Contact>.of(contacts);
        if (newIndex > oldIndex) newIndex -= 1;
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        ref.read(contactsNotifierProvider.notifier).reorder(reordered);
      },
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final unreachable = channels.emailRequiresAddress && !contact.hasEmail;
        return Padding(
          key: ValueKey(contact.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.space3),
          child: Dismissible(
            key: ValueKey('dismiss-${contact.id}'),
            direction: DismissDirection.endToStart,
            background: _DeleteBackground(),
            onDismissed: (_) => ref.read(contactsNotifierProvider.notifier).removeContact(contact.id),
            child: Column(
              children: [
                SaContactCard(
                  name: contact.name,
                  relationship: contact.relationship,
                  priority: index + 1,
                  confirmed: contact.confirmed,
                  dragHandle: ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      // A bare 18px glyph is well under the 44dp minimum for
                      // something you are meant to press and drag.
                      padding: EdgeInsets.all(AppSpacing.space3),
                      child: SaIcon(SaIconGlyph.dragHandle, size: 18),
                    ),
                  ),
                  onTap: () => onEdit(contact),
                ),
                if (unreachable)
                  _UnreachableNotice(onAddEmail: () => onEdit(contact))
                else if (!contact.confirmed && contact.hasEmail)
                  _UnverifiedNotice(onVerify: () => onVerify(contact)),
                _ContactActions(contact: contact),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Call / message shortcuts for a saved contact. Both hand off to the device's
/// own dialler and messaging app — SafeHer never places the call itself, and
/// says so plainly if the device has no app to handle it.
class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.contact});

  final Contact contact;

  static const _actions = ExternalActions();

  Future<void> _call(BuildContext context) async {
    if (await _actions.dial(contact.phone)) return;
    if (context.mounted) {
      showSaToast(context, message: 'No dialler available on this device', type: SaToastType.error);
    }
  }

  Future<void> _message(BuildContext context) async {
    if (await _actions.sendSms(contact.phone)) return;
    if (context.mounted) {
      showSaToast(context, message: 'No messaging app available', type: SaToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space2),
      child: Row(
        children: [
          Expanded(
            child: SaButton(
              label: 'Call',
              onPressed: () => _call(context),
              variant: SaButtonVariant.secondary,
              size: SaButtonSize.sm,
              semanticsLabel: 'Call ${contact.name}',
            ),
          ),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: SaButton(
              label: 'Message',
              onPressed: () => _message(context),
              variant: SaButtonVariant.secondary,
              size: SaButtonSize.sm,
              semanticsLabel: 'Message ${contact.name}',
            ),
          ),
        ],
      ),
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

/// Shown under a contact that an SOS cannot currently reach.
///
/// Deliberately specific about the cause and the remedy. A generic
/// "incomplete contact" badge would leave the user guessing, and the whole
/// point is that she can fix this in ten seconds by adding an address.
class _UnreachableNotice extends StatelessWidget {
  const _UnreachableNotice({required this.onAddEmail});

  final VoidCallback onAddEmail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.space2),
        padding: const EdgeInsets.all(AppSpacing.space3),
        decoration: BoxDecoration(
          color: AppColors.warning500.withValues(alpha: 0.12),
          borderRadius: AppRadius.mdRadius,
          border: Border.all(color: AppColors.warning500.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SaIcon(SaIconGlyph.bell, size: 16, color: AppColors.warning500),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'An alert can’t reach this contact',
                    style: AppTypography.labelM.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'SafeHer alerts by email, and this contact has no email '
                    'address. Text messaging isn’t available yet.',
                    style: AppTypography.bodyS.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  GestureDetector(
                    onTap: onAddEmail,
                    behavior: HitTestBehavior.opaque,
                    child: Semantics(
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
                        child: Text(
                          'Add an email address',
                          style: AppTypography.labelM.copyWith(color: AppColors.violet400),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown on a contact nobody at that address has confirmed (FR-EMG-10).
///
/// Quieter than the unreachable notice on purpose: an unverified contact
/// still gets alerted, so this is a "worth checking", not a "this will
/// fail". Ranking them the same would flatten the difference between a
/// contact who might not hear and one who definitely won't.
class _UnverifiedNotice extends StatelessWidget {
  const _UnverifiedNotice({required this.onVerify});

  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space2, left: AppSpacing.space1),
      child: Row(
        children: [
          SaIcon(SaIconGlyph.bell, size: 14, color: onSurface.withValues(alpha: 0.45)),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Text(
              'Not confirmed yet',
              style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.55)),
            ),
          ),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: onVerify,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
                child: Text(
                  'Confirm',
                  style: AppTypography.labelM.copyWith(color: AppColors.violet400),
                ),
              ),
            ),
          ),
        ],
      ),
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
