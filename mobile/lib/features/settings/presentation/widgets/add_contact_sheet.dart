import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/inputs/sa_text_field.dart';

/// Bottom sheet form for adding a new emergency contact. Pops with a
/// `(name, relationship)` record, or null if cancelled.
class AddContactSheet extends StatefulWidget {
  const AddContactSheet({super.key});

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  bool get _canSave => _nameController.text.trim().isNotEmpty && _relationshipController.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSave) return;
    Navigator.of(context).pop((_nameController.text.trim(), _relationshipController.text.trim()));
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
          Text('Add Emergency Contact', style: AppTypography.headingM.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(label: 'Name', controller: _nameController, onChanged: (_) => setState(() {})),
          const SizedBox(height: AppSpacing.space4),
          SaTextField(
            label: 'Relationship',
            controller: _relationshipController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.space5),
          SaButton(label: 'Add Contact', fullWidth: true, onPressed: _canSave ? _submit : null),
        ],
      ),
    );
  }
}
