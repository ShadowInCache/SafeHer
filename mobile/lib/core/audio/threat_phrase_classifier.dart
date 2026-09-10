import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// What the classifier decided about one utterance.
@immutable
class PhraseVerdict {
  const PhraseVerdict({
    required this.label,
    required this.probabilities,
    required this.elevated,
  });

  /// `threat`, `distress` or `normal` — the most likely single class.
  ///
  /// Carried for the incident record, not for the score. A woman shouting
  /// "he has a knife" and a man shouting "I'll cut you" are different
  /// sentences to describe afterwards and the same emergency at the time.
  final String label;

  /// Probability per class, keyed by class name.
  final Map<String, double> probabilities;

  /// `P(threat) + P(distress)` — the number the fusion engine consumes.
  ///
  /// This is the model's real output. The three-way label above is a
  /// description; this is the decision, and it is the boundary the model was
  /// tuned on. On held-out phrasings it reaches 0.920 accuracy at 0.968 recall
  /// against clean audio, and **0.831 at 0.883 against realistically degraded
  /// audio** — babble, traffic, distance, phone-band limiting and clipping.
  /// The second pair is the one worth quoting; the first is a text-to-speech
  /// voice reading calmly, which is not the moment this exists for.
  final double elevated;
}

/// Reads a transcript and scores how much it sounds like trouble.
///
/// ## Why a linear model and not a neural one
///
/// The strongest classifier measured on this task pairs TF-IDF with sentence
/// embeddings, at 0.852 three-way. It cannot ship: it needs an 88 MB
/// `all-MiniLM-L6-v2` encoder resident on the phone and a runtime to drive it,
/// for every utterance. This model is a vocabulary, an IDF vector and a
/// coefficient matrix — 370 kB of JSON and two loops — so it runs on Android
/// and on web with no native dependency, no platform channel, no download.
///
/// ## Preprocessing is a contract
///
/// The weights were fitted by scikit-learn, so the features must be built
/// exactly as scikit-learn builds them, or the coefficients are being applied
/// to the wrong numbers. Three details do the damage if missed:
///
///  * the word analyser drops single-character tokens — its pattern needs two
///    word characters — so "a" and "I" contribute nothing;
///  * `char_wb` pads every word with a leading and trailing space before
///    cutting n-grams, so " he" and "he " are distinct features;
///  * each vectoriser L2-normalises its own block *before* they are
///    concatenated. Normalising once at the end is a different function that
///    returns plausible-looking wrong answers.
///
/// Getting any of these wrong yields a classifier that is still confident and
/// now incorrect, on a safety input, with nothing on screen to indicate it. So
/// `threat_phrase_classifier_test.dart` asserts this implementation against
/// probabilities produced by the Python model on real transcripts, which turns
/// a silent drift into a failing build.
class ThreatPhraseClassifier {
  ThreatPhraseClassifier._({
    required List<String> classes,
    required List<_Vectoriser> vectorisers,
    required List<int> blockOffsets,
    required List<List<double>> coefficients,
    required List<double> intercepts,
  })  : _classes = classes,
        _vectorisers = vectorisers,
        _blockOffsets = blockOffsets,
        _coefficients = coefficients,
        _intercepts = intercepts;

  static const assetPath = 'assets/models/phrase_classifier.json';

  final List<String> _classes;
  final List<_Vectoriser> _vectorisers;
  final List<int> _blockOffsets;
  final List<List<double>> _coefficients;
  final List<double> _intercepts;

  /// Which classes count as "something is wrong".
  static const _elevatedClasses = {'threat', 'distress'};

  static ThreatPhraseClassifier fromJson(Map<String, dynamic> json) {
    final vectorisers = (json['vectorisers'] as List)
        .cast<Map<String, dynamic>>()
        .map(_Vectoriser.fromJson)
        .toList(growable: false);
    return ThreatPhraseClassifier._(
      classes: (json['classes'] as List).cast<String>(),
      vectorisers: vectorisers,
      blockOffsets: (json['block_offsets'] as List).cast<int>(),
      coefficients: (json['coef'] as List)
          .map(
            (row) => (row as List)
                .map((v) => (v as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false),
      intercepts: (json['intercept'] as List)
          .map((v) => (v as num).toDouble())
          .toList(growable: false),
    );
  }

  static Future<ThreatPhraseClassifier> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Lowercase, drop apostrophes, collapse everything else to single spaces.
  ///
  /// Mirrors `compare_matchers.normalise`. Apostrophes are removed rather than
  /// replaced with a space so "don't" becomes "dont" — one token, matching how
  /// the model was fitted — instead of "don t", where "t" would then be dropped
  /// for being a single character and the negation would vanish.
  @visibleForTesting
  static String normalise(String text) {
    final lowered = text.toLowerCase().replaceAll("'", '').replaceAll('’', '');
    final cleaned = lowered.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    return cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).join(' ');
  }

  PhraseVerdict classify(String transcript) {
    final text = normalise(transcript);

    final features = List<double>.filled(
      _blockOffsets.last + _vectorisers.last.terms.length,
      0,
    );
    var anyFeature = false;
    for (var i = 0; i < _vectorisers.length; i++) {
      anyFeature |= _vectorisers[i].fill(text, features, _blockOffsets[i]);
    }

    // Nothing in the transcript is a word this model knows — silence, noise,
    // or a recogniser that returned junk. Falling through would apply the
    // intercepts alone, and those are not neutral: `class_weight='balanced'`
    // fitted them across two elevated classes and one normal one, so an empty
    // input scores 0.56 elevated. A microphone hearing nothing would report
    // more than half-way to an emergency, continuously.
    //
    // "Nothing heard" and "nothing wrong" are different claims and this is the
    // only place that can tell them apart, so it refuses to guess.
    if (!anyFeature) {
      return PhraseVerdict(
        label: 'normal',
        probabilities: {for (final name in _classes) name: name == 'normal' ? 1.0 : 0.0},
        elevated: 0,
      );
    }

    final logits = List<double>.generate(
      _classes.length,
      (c) {
        var sum = _intercepts[c];
        final row = _coefficients[c];
        for (var j = 0; j < features.length; j++) {
          if (features[j] != 0) sum += row[j] * features[j];
        }
        return sum;
      },
      growable: false,
    );

    final probabilities = _softmax(logits);
    var bestIndex = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[bestIndex]) bestIndex = i;
    }

    var elevated = 0.0;
    final byName = <String, double>{};
    for (var i = 0; i < _classes.length; i++) {
      byName[_classes[i]] = probabilities[i];
      if (_elevatedClasses.contains(_classes[i])) elevated += probabilities[i];
    }

    return PhraseVerdict(
      label: _classes[bestIndex],
      probabilities: byName,
      elevated: elevated.clamp(0.0, 1.0),
    );
  }

  static List<double> _softmax(List<double> logits) {
    final peak = logits.reduce(math.max);
    final exponentials =
        logits.map((v) => math.exp(v - peak)).toList(growable: false);
    final total = exponentials.reduce((a, b) => a + b);
    return exponentials.map((v) => v / total).toList(growable: false);
  }
}

/// One scikit-learn `TfidfVectorizer`, reduced to the tables it needs.
class _Vectoriser {
  _Vectoriser({
    required this.analyzer,
    required this.ngramMin,
    required this.ngramMax,
    required this.sublinearTf,
    required this.terms,
    required this.idf,
  }) : _index = {for (var i = 0; i < terms.length; i++) terms[i]: i};

  factory _Vectoriser.fromJson(Map<String, dynamic> json) => _Vectoriser(
        analyzer: json['analyzer'] as String,
        ngramMin: json['ngram_min'] as int,
        ngramMax: json['ngram_max'] as int,
        sublinearTf: json['sublinear_tf'] as bool,
        terms: (json['terms'] as List).cast<String>(),
        idf: (json['idf'] as List)
            .map((v) => (v as num).toDouble())
            .toList(growable: false),
      );

  final String analyzer;
  final int ngramMin;
  final int ngramMax;
  final bool sublinearTf;
  final List<String> terms;
  final List<double> idf;
  final Map<String, int> _index;

  /// scikit-learn's default `token_pattern`, which requires two or more word
  /// characters. Single letters are deliberately not tokens.
  static final _tokenPattern = RegExp(r'\w\w+');

  /// Writes this vectoriser's L2-normalised block into [out] at [offset].
  ///
  /// Returns whether any known term was found, so the caller can tell an
  /// utterance this model has opinions about from one it has never seen a
  /// single word of.
  bool fill(String text, List<double> out, int offset) {
    final counts = <int, int>{};
    for (final term in _analyse(text)) {
      final column = _index[term];
      if (column != null) counts.update(column, (v) => v + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return false;

    var squared = 0.0;
    final weighted = <int, double>{};
    counts.forEach((column, count) {
      final tf = sublinearTf ? 1.0 + math.log(count) : count.toDouble();
      final value = tf * idf[column];
      weighted[column] = value;
      squared += value * value;
    });

    // L2 over this block alone. The union concatenates already-normalised
    // blocks; one norm across the joined vector is a different transform.
    final norm = math.sqrt(squared);
    if (norm == 0) return false;
    weighted.forEach((column, value) => out[offset + column] = value / norm);
    return true;
  }

  Iterable<String> _analyse(String text) =>
      analyzer == 'char_wb' ? _charWordBoundaryNgrams(text) : _wordNgrams(text);

  Iterable<String> _wordNgrams(String text) sync* {
    final tokens =
        _tokenPattern.allMatches(text).map((m) => m[0]!).toList(growable: false);
    for (var n = ngramMin; n <= ngramMax; n++) {
      for (var start = 0; start + n <= tokens.length; start++) {
        yield tokens.sublist(start, start + n).join(' ');
      }
    }
  }

  /// scikit-learn's `_char_wb_ngrams`, transcribed.
  ///
  /// Each word is padded with a space on both sides, then cut into n-grams. A
  /// word shorter than `n` still yields exactly one padded n-gram — that is
  /// the `break` below, and dropping it silently changes the feature set for
  /// every short word in the language.
  Iterable<String> _charWordBoundaryNgrams(String text) sync* {
    for (final word in text.split(' ')) {
      if (word.isEmpty) continue;
      final padded = ' $word ';
      final length = padded.length;
      for (var n = ngramMin; n <= ngramMax; n++) {
        var offset = 0;
        yield padded.substring(offset, math.min(offset + n, length));
        while (offset + n < length) {
          offset += 1;
          yield padded.substring(offset, offset + n);
        }
        if (offset == 0) break;
      }
    }
  }
}
