import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/audio/threat_phrase_classifier.dart';

/// The classifier's weights were fitted by scikit-learn and are executed by
/// hand-written Dart. Nothing about that arrangement is self-checking: if the
/// Dart builds its features even slightly differently, the coefficients are
/// applied to the wrong numbers and the model goes on returning confident,
/// wrong answers with no error anywhere.
///
/// So the real test is not "does it classify this sentence sensibly" — it is
/// **does it produce the same probabilities the Python model produced**, on
/// real transcripts, to several decimal places. `phrase_classifier_fixtures.json`
/// is written by `export_phrase_classifier.py` from the same fitted pipeline
/// that produced the shipped weights.
void main() {
  late ThreatPhraseClassifier classifier;
  late Map<String, dynamic> fixtures;

  setUpAll(() {
    classifier = ThreatPhraseClassifier.fromJson(
      jsonDecode(File('assets/models/phrase_classifier.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    fixtures = jsonDecode(
      File('test/core/audio/fixtures/phrase_classifier_fixtures.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('parity with the Python model', () {
    test('reproduces scikit-learn probabilities on every fixture', () {
      final classes = (fixtures['classes'] as List).cast<String>();
      final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();

      expect(cases, isNotEmpty, reason: 'fixtures file is empty');

      var worstError = 0.0;
      String? worstText;

      for (final testCase in cases) {
        final text = testCase['text'] as String;
        final expected = (testCase['probabilities'] as List)
            .map((v) => (v as num).toDouble())
            .toList();

        final verdict = classifier.classify(text);

        for (var i = 0; i < classes.length; i++) {
          final actual = verdict.probabilities[classes[i]]!;
          final error = (actual - expected[i]).abs();
          if (error > worstError) {
            worstError = error;
            worstText = text;
          }
          expect(
            actual,
            closeTo(expected[i], 1e-4),
            reason: 'class "${classes[i]}" diverged on "$text" — the Dart '
                'feature extraction no longer matches scikit-learn',
          );
        }
      }

      // Surfaced even on success: a creeping error is worth seeing before it
      // crosses the threshold and fails the build with no history behind it.
      // ignore: avoid_print
      print('worst probability error $worstError (on "$worstText")');
    });

    test('elevated score is the sum of threat and distress', () {
      for (final testCase
          in (fixtures['cases'] as List).cast<Map<String, dynamic>>()) {
        final verdict = classifier.classify(testCase['text'] as String);
        expect(
          verdict.elevated,
          closeTo(
            verdict.probabilities['threat']! +
                verdict.probabilities['distress']!,
            1e-9,
          ),
        );
        expect(verdict.elevated, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('preprocessing contract', () {
    test('strips apostrophes rather than splitting on them', () {
      // "dont" is one token the model was fitted on. "don t" would lose the
      // negation entirely, because single characters are not tokens.
      expect(ThreatPhraseClassifier.normalise("Don't touch me"), 'dont touch me');
      expect(ThreatPhraseClassifier.normalise('Don’t touch me'), 'dont touch me');
    });

    test('lowercases and collapses punctuation and whitespace', () {
      expect(
        ThreatPhraseClassifier.normalise('  HELP!!  Please... HELP  '),
        'help please help',
      );
    });

    test('an empty or unintelligible transcript is not elevated', () {
      // A silent window must read as "nothing heard", never as "nothing
      // wrong" with confidence. With no features at all the model falls back
      // to its intercepts, and `normal` must win there.
      for (final text in ['', '   ', '...', '!!!']) {
        final verdict = classifier.classify(text);
        expect(verdict.label, 'normal', reason: 'empty input "$text"');
        expect(verdict.elevated, lessThan(0.5));
      }
    });
  });

  group('behaviour that matters at the boundary', () {
    test('scores calls for help above ordinary conversation', () {
      final distress = classifier.classify('please someone help me');
      final ordinary = classifier.classify('what time is the bus');

      expect(distress.elevated, greaterThan(0.5));
      expect(ordinary.elevated, lessThan(0.5));
      expect(distress.elevated, greaterThan(ordinary.elevated));
    });

    test('scores an explicit threat above ordinary conversation', () {
      expect(classifier.classify('i will hurt you').elevated, greaterThan(0.5));
    });
  });
}
