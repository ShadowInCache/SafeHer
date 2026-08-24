import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/inputs/sa_text_field.dart';
import '../../../contacts/data/contacts_providers.dart';

/// What the user chose when starting a journey.
class StartJourneyConfig {
  const StartJourneyConfig({
    required this.destinationLabel,
    required this.expectedDurationMinutes,
    required this.contactIds,
    this.checkInIntervalMinutes,
  });

  final String destinationLabel;
  final int expectedDurationMinutes;
  final int? checkInIntervalMinutes;
  final List<String> contactIds;
}

/// Configure and start a Safe Journey. The contact list comes from the user's
/// real emergency contacts — there is no separate journey contact book.
class StartJourneySheet extends ConsumerStatefulWidget {
  const StartJourneySheet({super.key});

  @override
  ConsumerState<StartJourneySheet> createState() => _StartJourneySheetState();
}

class _StartJourneySheetState extends ConsumerState<StartJourneySheet> {
  final _destinationController = TextEditingController();
  final _selectedContactIds = <String>{};

  int _durationMinutes = 30;
  String? _destinationError;

  static const _durationOptions = [15, 30, 45, 60, 90, 120];

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  void _submit() {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      setState(() => _destinationError = 'Where are you heading?');
      return;
    }

    Navigator.of(context).pop(
      StartJourneyConfig(
        destinationLabel: destination,
        expectedDurationMinutes: _durationMinutes,
        contactIds: _selectedContactIds.toList(),
        // Check-ins fire at roughly the journey's midpoint by default; the
        // user can still check in manually whenever they like.
        checkInIntervalMinutes: _durationMinutes >= 30 ? (_durationMinutes ~/ 2) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final contactsAsync = ref.watch(contactsNotifierProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenMarginPhone,
        right: AppSpacing.screenMarginPhone,
        top: AppSpacing.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start Safe Journey', style: AppTypography.headingM.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(
            label: 'Destination',
            controller: _destinationController,
            errorText: _destinationError,
            onChanged: (_) {
              if (_destinationError != null) setState(() => _destinationError = null);
            },
          ),
          const SizedBox(height: AppSpacing.space5),
          Text('Expected duration', style: AppTypography.labelL.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              for (final minutes in _durationOptions)
                _DurationChip(
                  minutes: minutes,
                  isSelected: _durationMinutes == minutes,
                  onTap: () => setState(() => _durationMinutes = minutes),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.space5),
          Text('Notify if overdue', style: AppTypography.labelL.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          contactsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.space3),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Text(
              "Couldn't load your contacts — you can still start the journey.",
              style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
            ),
            data: (contacts) => contacts.isEmpty
                ? Text(
                    'No emergency contacts yet. Add one in Settings so someone is '
                    'told if you don\'t arrive.',
                    style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                  )
                : Column(
                    children: [
                      for (final contact in contacts)
                        CheckboxListTile(
                          value: _selectedContactIds.contains(contact.id),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selectedContactIds.add(contact.id);
                            } else {
                              _selectedContactIds.remove(contact.id);
                            }
                          }),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            contact.name,
                            style: AppTypography.bodyM.copyWith(color: onSurface),
                          ),
                          subtitle: Text(
                            contact.relationship,
                            style: AppTypography.bodyS.copyWith(
                              color: onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.space5),
          SaButton(label: 'Start journey', onPressed: _submit, fullWidth: true),
        ],
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.minutes, required this.isSelected, required this.onTap});

  final int minutes;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final label = minutes >= 60
        ? '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}m'}'
        : '$minutes min';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTypography.labelM.copyWith(
            color: isSelected ? Theme.of(context).colorScheme.onPrimary : onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}
