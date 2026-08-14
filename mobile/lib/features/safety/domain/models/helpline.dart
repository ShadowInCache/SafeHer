/// A published emergency helpline.
///
/// Sourced deliberately, not scraped or invented — see [IndiaHelplines] for
/// the provenance of every number in the shipped list. Numbers change; each
/// entry records where it came from and when it was last checked so it can be
/// re-verified rather than trusted indefinitely.
class Helpline {
  const Helpline({
    required this.name,
    required this.number,
    required this.description,
    required this.source,
    required this.lastVerified,
    this.isPrimary = false,
  });

  final String name;
  final String number;
  final String description;

  /// Where this number was taken from, so a future maintainer can re-check it.
  final String source;
  final String lastVerified;

  /// Rendered first and emphasised — the number to call when unsure.
  final bool isPrimary;
}

/// India's national helplines.
///
/// SafeHer's backend has no country-detection or helpline directory service,
/// so this list is scoped to one country rather than pretending to be global:
/// showing an Indian number to a user in another country would be worse than
/// showing none. The screen states the scope plainly.
///
/// All numbers below are the nationally published ones listed by the National
/// Commission for Women and the Ministry of Home Affairs' 112 India service.
abstract final class IndiaHelplines {
  static const _source = 'National Commission for Women / MHA 112 India';
  static const _verified = '2026-08';

  static const all = <Helpline>[
    Helpline(
      name: 'Emergency Response Support System',
      number: '112',
      description: 'Single emergency number — police, fire, and ambulance.',
      source: _source,
      lastVerified: _verified,
      isPrimary: true,
    ),
    Helpline(
      name: 'Women Helpline (All India)',
      number: '1091',
      description: 'Women in distress, 24x7.',
      source: _source,
      lastVerified: _verified,
      isPrimary: true,
    ),
    Helpline(
      name: 'Domestic Abuse Helpline',
      number: '181',
      description: 'Women affected by violence, including domestic abuse.',
      source: _source,
      lastVerified: _verified,
    ),
    Helpline(
      name: 'Police',
      number: '100',
      description: 'Direct police control room.',
      source: _source,
      lastVerified: _verified,
    ),
    Helpline(
      name: 'Ambulance',
      number: '102',
      description: 'Medical emergency transport.',
      source: _source,
      lastVerified: _verified,
    ),
    Helpline(
      name: 'Fire',
      number: '101',
      description: 'Fire and rescue services.',
      source: _source,
      lastVerified: _verified,
    ),
    Helpline(
      name: 'Child Helpline',
      number: '1098',
      description: 'Children in need of care and protection.',
      source: _source,
      lastVerified: _verified,
    ),
    Helpline(
      name: 'Cyber Crime Helpline',
      number: '1930',
      description: 'Online financial fraud and cyber crime.',
      source: _source,
      lastVerified: _verified,
    ),
  ];
}
