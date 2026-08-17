import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/detection/detection_status.dart';

/// What the app is allowed to claim about automatic detection.
///
/// The Profile screen's threat-threshold slider governs SRS FR-EMG-02. The
/// threshold now reaches the server and the server acts on it, but the
/// decision needs a *score*, and no detection model is trained yet. A control
/// that silently governs nothing is indistinguishable from protection, which
/// on a safety app is the failure that matters: a woman who believes SafeHer
/// is watching may not watch for herself.
void main() {
  DetectionStatus statusFrom(Map<String, dynamic> json) => DetectionStatus.fromJson(json);

  group('what the backend says', () {
    test('no trained model means automatic detection is off', () {
      final status = statusFrom({
        'any_ready': false,
        'pipeline_live': false,
        'scores_are_caller_supplied': true,
        'models': [
          {
            'modality': 'motion',
            'algorithm': 'XGBoost',
            'source_device': 'glove',
            'status': 'untrained',
          },
        ],
      });

      expect(status.autoSosActive, isFalse);
      expect(status.headline, contains('not active'));
    });

    test('one serving model is enough to be scoring something', () {
      // Partial coverage is the normal case: the glove can be transmitting
      // while the glasses are off. That is still real detection.
      final status = statusFrom({'any_ready': true, 'pipeline_live': false});

      expect(status.autoSosActive, isTrue);
      expect(status.headline, contains('on'));
    });
  });

  group('the copy never overstates', () {
    test('the inactive message says what still protects her', () {
      // "Detection is off" on its own reads as "the app is broken". It is
      // not: SOS, the shake gesture and contact alerting all work.
      final status = statusFrom({'any_ready': false});

      expect(status.detail, contains('SOS'));
      expect(status.detail, contains('shake'));
      expect(status.detail, contains('contacts'));
    });

    test('the inactive message never promises detection', () {
      final detail = statusFrom({'any_ready': false}).detail.toLowerCase();

      expect(detail.contains('will detect'), isFalse);
      expect(detail.contains('is monitoring'), isFalse);
    });
  });

  group('unknown fails safe', () {
    test('an unreachable backend reports detection as off, not on', () {
      // The one error worth avoiding: claiming detection is running when we
      // do not know could stop someone acting for herself.
      expect(DetectionStatus.unknown.autoSosActive, isFalse);
      expect(DetectionStatus.unknown.scoresAreCallerSupplied, isTrue);
    });

    test('a malformed payload does not throw and does not claim detection', () {
      // An older backend without this endpoint, or a proxy returning
      // something unexpected, must degrade rather than crash the screen.
      final status = statusFrom(const {});

      expect(status.autoSosActive, isFalse);
      expect(status.models, isEmpty);
    });
  });

  group('model descriptions', () {
    test('a model is described in the user\'s terms, not the system\'s', () {
      final model = DetectionModel.fromJson(const {
        'modality': 'vision',
        'algorithm': 'YOLOv8',
        'source_device': 'glasses',
        'status': 'untrained',
      });

      expect(model.label, 'Vision from the glasses');
      expect(model.isReady, isFalse);
    });

    test('ready is the only status that counts as ready', () {
      // "untrained" and "unavailable" need different responses from an
      // operator, and neither means the model is serving.
      for (final status in ['untrained', 'unavailable', 'anything else']) {
        expect(
          DetectionModel.fromJson({'status': status}).isReady,
          isFalse,
          reason: status,
        );
      }
      expect(DetectionModel.fromJson(const {'status': 'ready'}).isReady, isTrue);
    });
  });
}
