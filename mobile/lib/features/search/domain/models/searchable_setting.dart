/// A static index of jump-to-able settings entries, searched by [label] —
/// there's no backend for this (Settings isn't a data list), so it's a
/// fixed table matching the real rows on `/settings` and `/profile`.
class SearchableSetting {
  const SearchableSetting({required this.label, required this.description, required this.route});

  final String label;
  final String description;
  final String route;
}

const searchableSettings = [
  SearchableSetting(label: 'Profile', description: 'Name, email, and account overview', route: '/profile'),
  SearchableSetting(
    label: 'Emergency Contacts',
    description: 'Who gets notified during an alert',
    route: '/settings/contacts',
  ),
  SearchableSetting(label: 'Paired Devices', description: 'Manage your smart devices', route: '/devices'),
  SearchableSetting(label: 'Push Notifications', description: 'Alerts and device status updates', route: '/settings'),
  SearchableSetting(label: 'SMS Notifications', description: 'Text message alerts', route: '/settings'),
  SearchableSetting(label: 'Email Notifications', description: 'Weekly safety summaries', route: '/settings'),
  SearchableSetting(
    label: 'Location Sharing',
    description: 'Share live location during an alert',
    route: '/settings',
  ),
  SearchableSetting(label: 'Threat Threshold', description: 'AI auto-SOS sensitivity', route: '/profile'),
  SearchableSetting(label: 'Countdown Duration', description: 'SOS cancellable countdown length', route: '/profile'),
  SearchableSetting(label: 'Biometric Unlock', description: 'Face ID / Fingerprint', route: '/profile'),
  SearchableSetting(label: 'Dark Mode', description: 'App appearance', route: '/settings'),
];
