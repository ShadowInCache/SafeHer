import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/inputs/sa_otp_field.dart';
import '../../../../shared/utils/user_error.dart';
import '../../../contacts/data/contacts_providers.dart';
import '../../../contacts/domain/models/contact.dart';

/// Confirms that an emergency contact's email actually reaches them
/// (SRS FR-EMG-10).
///
/// The code goes to the contact, not the user, and they read it back — so
/// the copy has to explain that, or the user sits waiting for an email that
/// was never addressed to her.
class VerifyContactSheet extends ConsumerStatefulWidget {
  const VerifyContactSheet({required this.contact, super.key});

  final Contact contact;

  @override
  ConsumerState<VerifyContactSheet> createState() => _VerifyContactSheetState();
}

class _VerifyContactSheetState extends ConsumerState<VerifyContactSheet> {
  bool _sending = false;
  bool _sent = false;
  bool _confirming = false;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final alreadyVerified =
          await ref.read(contactsNotifierProvider.notifier).sendVerificationCode(widget.contact.id);
      if (!mounted) return;
      if (alreadyVerified) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = describeError(error, fallbackTitle: 'Couldn’t send the code').message;
      });
    }
  }

  Future<void> _confirm(String code) async {
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await ref
          .read(contactsNotifierProvider.notifier)
          .confirmVerificationCode(widget.contact.id, code);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = describeError(error, fallbackTitle: 'That didn’t work').message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm ${widget.contact.name}',
            style: AppTypography.headingM.copyWith(color: onSurface),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            _sent
                ? 'We emailed a 6-digit code to ${widget.contact.email}. '
                      'Ask ${widget.contact.name} to read it out, then enter it below.'
                : 'We’ll email a 6-digit code to ${widget.contact.email}. '
                      '${widget.contact.name} reads it back to you, which proves '
                      'the address really reaches them.',
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: AppSpacing.space5),
          if (_sent) ...[
            SaOTPField(onCompleted: _confirming ? (_) {} : _confirm),
            if (_confirming) ...[
              const SizedBox(height: AppSpacing.space4),
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ] else
            SaButton(
              label: 'Send code',
              fullWidth: true,
              isLoading: _sending,
              onPressed: _sending ? null : _send,
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.space3),
            Text(
              _error!,
              style: AppTypography.bodyS.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_sent) ...[
            const SizedBox(height: AppSpacing.space3),
            TextButton(
              onPressed: _sending ? null : _send,
              child: const Text('Send a new code'),
            ),
          ],
          const SizedBox(height: AppSpacing.space2),
        ],
      ),
    );
  }
}
