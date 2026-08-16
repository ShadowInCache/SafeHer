import 'package:flutter/foundation.dart';

/// Which emergency channels the backend can actually deliver on, from
/// `GET /api/v1/alerts/channels`.
///
/// The app cannot infer this. Whether SMS works depends on server-side
/// credentials the client never sees, and getting it wrong on the contacts
/// screen means showing a phone-only contact as ready while an SOS would
/// reach nobody — telling a user her sister will be called when she won't.
@immutable
class AlertChannels {
  const AlertChannels({
    required this.sms,
    required this.email,
    required this.push,
  });

  /// Assumed while the real answer is loading, and after a failure to fetch
  /// it. Deliberately optimistic: an unreachable-contact warning shown in
  /// error would train users to ignore it, and the warning is only useful
  /// if it is rare and true.
  const AlertChannels.optimistic() : sms = true, email = true, push = true;

  final bool sms;
  final bool email;
  final bool push;

  /// True when email is the only channel that reaches an ordinary contact,
  /// so a contact without an address cannot be reached at all.
  bool get emailRequiresAddress => email && !sms;

  /// True when nothing can reach a contact who hasn't installed SafeHer.
  bool get noContactChannel => !sms && !email;

  factory AlertChannels.fromJson(Map<String, dynamic> json) => AlertChannels(
    sms: json['sms'] as bool? ?? false,
    email: json['email'] as bool? ?? false,
    push: json['push'] as bool? ?? false,
  );
}
