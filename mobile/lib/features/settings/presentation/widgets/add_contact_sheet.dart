import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/inputs/sa_text_field.dart';

/// Bottom sheet form for adding a new emergency contact. Pops with a
/// `(name, phone, relationship, email)` record, or null if cancelled.
///
/// Phone is required — the backend rejects a contact without one, and it is
/// what a call falls back to. Email is optional but strongly encouraged in
/// the copy below, because it is the one emergency channel this project can
/// run for free: SMS costs money with every provider, while OneSignal's free
/// tier covers 10,000 emails a month. A contact with no email address can
/// only be reached if SMS credit exists.
class AddContactSheet extends StatefulWidget {
  const AddContactSheet({
    super.key,
    this.initialName,
    this.initialPhone,
    this.initialRelationship,
    this.initialEmail,
  });

  /// When supplied, the sheet edits an existing contact instead of adding
  /// one. Editing exists mainly so a contact saved without an email can be
  /// given one: while SMS is unconfigured, an address is the only thing
  /// that makes them reachable, and the previous alternative was deleting
  /// the contact and retyping it.
  final String? initialName;
  final String? initialPhone;
  final String? initialRelationship;
  final String? initialEmail;

  bool get isEditing => initialName != null;

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  late final _nameController = TextEditingController(text: widget.initialName ?? '');
  late final _phoneController = TextEditingController(text: widget.initialPhone ?? '');
  late final _relationshipController =
      TextEditingController(text: widget.initialRelationship ?? '');
  late final _emailController = TextEditingController(text: widget.initialEmail ?? '');

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Permissive on purpose. This is a nudge, not a gate: a contact with a
  /// slightly odd address is better than one the user abandoned because the
  /// form argued with them mid-setup.
  bool get _emailLooksValid {
    final value = _emailController.text.trim();
    if (value.isEmpty) return true;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().replaceAll(RegExp(r'\s'), '').length >= 5 &&
      _relationshipController.text.trim().isNotEmpty &&
      _emailLooksValid;

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop((
      _nameController.text.trim(),
      _phoneController.text.trim(),
      _relationshipController.text.trim(),
      _emailController.text.trim(),
    ));
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
            widget.isEditing ? 'Edit Emergency Contact' : 'Add Emergency Contact',
            style: AppTypography.headingM.copyWith(color: onSurface),
          ),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(label: 'Name', controller: _nameController, onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(
            label: 'Phone number',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            semanticsLabel: 'Phone number',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(
            label: 'Relationship',
            controller: _relationshipController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(
            label: 'Email (recommended)',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            semanticsLabel: 'Email address, recommended',
            errorText: _emailLooksValid ? null : 'That doesn’t look like an email address.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'SafeHer always emails your contacts during an emergency. '
            'Without an address, this contact can only be reached by SMS.',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.space5),
          SaButton(
            label: widget.isEditing ? 'Save Changes' : 'Add Contact',
            fullWidth: true,
            onPressed: _canSave ? _submit : null,
          ),
        ],
      ),
    );
  }
}
