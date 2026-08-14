/// A short, original safety guide.
///
/// Written for SafeHer rather than copied from anywhere — the reference
/// project bundled third-party articles and YouTube embeds whose licensing
/// couldn't be established. These are deliberately brief: this section
/// complements the wearable system, it isn't the product.
class SafetyGuide {
  const SafetyGuide({
    required this.id,
    required this.category,
    required this.title,
    required this.summary,
    required this.points,
  });

  final String id;
  final SafetyGuideCategory category;
  final String title;
  final String summary;
  final List<String> points;
}

enum SafetyGuideCategory {
  personal,
  travel,
  digital,
  preparedness,
  selfDefence,
  situational;

  String get label => switch (this) {
    SafetyGuideCategory.personal => 'Personal safety',
    SafetyGuideCategory.travel => 'Travel safety',
    SafetyGuideCategory.digital => 'Digital safety',
    SafetyGuideCategory.preparedness => 'Emergency preparedness',
    SafetyGuideCategory.selfDefence => 'Self-defence awareness',
    SafetyGuideCategory.situational => 'Situational awareness',
  };
}

abstract final class SafetyGuides {
  static const all = <SafetyGuide>[
    SafetyGuide(
      id: 'trust-the-signal',
      category: SafetyGuideCategory.situational,
      title: 'Trust the early signal',
      summary: 'The discomfort you notice before you can explain it is information.',
      points: [
        'If a situation feels wrong, you do not owe anyone an explanation for leaving it.',
        'Leaving early is cheap. Leaving late is not.',
        'Say the plain thing — "I need to go" — rather than inventing a reason you then have to defend.',
        'A scheduled Fake Call gives you a reason to step away without a confrontation.',
      ],
    ),
    SafetyGuide(
      id: 'plan-the-route',
      category: SafetyGuideCategory.travel,
      title: 'Plan the route before you set off',
      summary: 'Decisions are easier to make before you are tired, late, or rushed.',
      points: [
        'Start a Safe Journey so someone knows where you were heading and by when.',
        'Prefer lit, populated routes over the shortest one, especially after dark.',
        'Share the vehicle number with a contact before you get in, not after.',
        'Sit where you can see the door and reach an exit.',
        'Keep one hand and one ear free — both earbuds in removes a whole sense.',
      ],
    ),
    SafetyGuide(
      id: 'know-your-exits',
      category: SafetyGuideCategory.situational,
      title: 'Know your exits',
      summary: 'In an unfamiliar place, find the way out before you need it.',
      points: [
        'On arriving somewhere new, note the exits and the busiest direction.',
        'Identify a staffed counter, a shop, or a lit forecourt you could walk into.',
        'Nearby Safety lists real police stations and hospitals around you.',
        'Walking towards people is usually safer than walking away from a place.',
      ],
    ),
    SafetyGuide(
      id: 'create-distance',
      category: SafetyGuideCategory.selfDefence,
      title: 'Distance is the goal',
      summary: 'Self-defence is about creating the space to leave, not winning a fight.',
      points: [
        'The aim is always to break away and get to people, not to stand your ground.',
        'Be loud and specific — "step back" carries further than a scream and is harder to dismiss.',
        'Keep obstacles between you and someone following you.',
        'Hands up and open in front of you protects your head and looks non-aggressive to witnesses.',
        'Practical technique needs a real instructor and real practice — reading about it is not training.',
      ],
    ),
    SafetyGuide(
      id: 'ready-before-you-need-it',
      category: SafetyGuideCategory.preparedness,
      title: 'Set it up before you need it',
      summary: 'Nothing here works well if it is first configured during an emergency.',
      points: [
        'Add at least two emergency contacts and put the most reachable one first.',
        'Set a Safety PIN so a mistaken SOS can be stood down and a real one cannot.',
        'Charge and pair your Smart Glove or Glasses before you leave.',
        'Check that location permission is granted — an SOS without a position is much less useful.',
        'Tell your contacts they are your contacts, so a SafeHer alert is not the first they hear of it.',
      ],
    ),
    SafetyGuide(
      id: 'digital-footprint',
      category: SafetyGuideCategory.digital,
      title: 'Mind what you broadcast',
      summary: 'Location and routine are the two things worth protecting most.',
      points: [
        'Post about where you were, not where you are.',
        'Turn off precise location sharing in apps that do not need it.',
        'A predictable routine posted publicly is the most useful thing you can give someone following you.',
        'Review which apps have background location access every few months.',
        'Share live location with people you chose, for a window you chose — not indefinitely.',
      ],
    ),
    SafetyGuide(
      id: 'if-you-are-followed',
      category: SafetyGuideCategory.personal,
      title: 'If you think you are being followed',
      summary: 'Confirm, redirect, and get to people — in that order.',
      points: [
        'Cross the road, or take two turns in a row, to confirm it is not coincidence.',
        'Do not go home. Head for somewhere staffed and lit.',
        'Call someone and say out loud where you are and where you are going.',
        'Trigger SOS early — it is far easier to stand down an alert than to raise one late.',
      ],
    ),
  ];

  static List<SafetyGuide> byCategory(SafetyGuideCategory category) =>
      all.where((guide) => guide.category == category).toList();
}
