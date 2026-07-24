import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/emergency_contact.dart';
import '../../providers/emergency_contact_provider.dart';

/// Add/Edit Emergency Contact Screen
class AddEmergencyContactScreen extends ConsumerStatefulWidget {
  final String userId;
  final EmergencyContact? contact;
  final bool isEditing;

  const AddEmergencyContactScreen({
    super.key,
    required this.userId,
    this.contact,
  }) : isEditing = contact != null;

  @override
  ConsumerState<AddEmergencyContactScreen> createState() =>
      _AddEmergencyContactScreenState();
}

class _AddEmergencyContactScreenState
    extends ConsumerState<AddEmergencyContactScreen> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late String _selectedRelationship;
  late int _selectedPriority;
  bool _isLoading = false;
  String? _errorMessage;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    if (widget.isEditing && widget.contact != null) {
      _nameController = TextEditingController(text: widget.contact!.name);
      _phoneController = TextEditingController(
        text: widget.contact!.phoneNumber,
      );
      _emailController = TextEditingController(
        text: widget.contact!.email ?? '',
      );
      _selectedRelationship = widget.contact!.relationship;
      _selectedPriority = widget.contact!.priority;
    } else {
      _nameController = TextEditingController();
      _phoneController = TextEditingController();
      _emailController = TextEditingController();
      _selectedRelationship = 'friend';
      _selectedPriority = 3;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit Emergency Contact' : 'Add Emergency Contact',
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() => _errorMessage = null);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Name *',
                  hintText: 'Enter contact name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Name is required';
                  }
                  if (value.length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Phone field
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: 'Enter phone number',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Phone number is required';
                  }
                  // Simple validation - at least 10 digits
                  final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
                  if (digitsOnly.length < 10) {
                    return 'Phone number must have at least 10 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Email field
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email (Optional)',
                  hintText: 'Enter email address',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    // Simple email validation
                    if (!RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                    ).hasMatch(value)) {
                      return 'Enter a valid email address';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Relationship dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedRelationship,
                decoration: InputDecoration(
                  labelText: 'Relationship *',
                  prefixIcon: const Icon(Icons.group),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items:
                    const [
                          DropdownMenuItem(
                            value: 'friend',
                            child: Text('Friend'),
                          ),
                          DropdownMenuItem(
                            value: 'family',
                            child: Text('Family'),
                          ),
                          DropdownMenuItem(
                            value: 'colleague',
                            child: Text('Colleague'),
                          ),
                          DropdownMenuItem(
                            value: 'emergency_service',
                            child: Text('Emergency Service'),
                          ),
                        ]
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item.value,
                            child: item.child,
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRelationship = value);
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a relationship';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Priority slider
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Priority ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getPriorityColor(
                            _selectedPriority,
                          ).withValues(alpha: 0.2),
                          border: Border.all(
                            color: _getPriorityColor(_selectedPriority),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Priority $_selectedPriority',
                          style: TextStyle(
                            color: _getPriorityColor(_selectedPriority),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: _selectedPriority.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _selectedPriority.toString(),
                    onChanged: (value) {
                      setState(() => _selectedPriority = value.toInt());
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Highest',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          'Lowest',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Submit button
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.isEditing ? 'Update Contact' : 'Add Contact',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(emergencyContactNotifierProvider.notifier);

      if (widget.isEditing && widget.contact != null) {
        // Update existing contact
        await notifier.updateContact(
          contactId: widget.contact!.contactId,
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          relationship: _selectedRelationship,
          priority: _selectedPriority,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contact updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        // Add new contact
        await notifier.addContact(
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          relationship: _selectedRelationship,
          priority: _selectedPriority,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contact added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Color _getPriorityColor(int priority) {
    if (priority <= 2) {
      return Colors.red;
    } else if (priority <= 4) {
      return Colors.orange;
    } else if (priority <= 6) {
      return Colors.amber;
    } else {
      return Colors.blue;
    }
  }
}
