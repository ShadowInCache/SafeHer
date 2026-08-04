class ManagedContact {
  const ManagedContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.confirmed,
  });

  final String id;
  final String name;
  final String relationship;
  final bool confirmed;
}
