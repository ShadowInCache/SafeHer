"""The app and the backend must agree on the names in the `/alerts/analyze` body.

This is the one seam in the detection pipeline that neither test suite covers.
`ThreatSignalAggregator.buildPayload()` writes the JSON; `ModelScoresRequest`
reads it. Both sides are thoroughly tested against their *own* idea of the wire
names, and nothing checks that the two ideas match.

Rename `vision_score` on either side and all 1,594 tests stay green while the
weapon signal silently stops reaching fusion. That failure is invisible for the
worst possible reason: the engine is built so a missing modality is *dropped
and the weights renormalised*, so there is no error, no log line and no crash —
the fused score simply stops including what the camera saw.

So this test reads the Dart source and asserts the contract directly.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from fastapi_app.schemas import ModelScoresRequest

AGGREGATOR = (
    Path(__file__).resolve().parents[1]
    / "mobile" / "lib" / "features" / "safety" / "data"
    / "threat_signal_aggregator.dart"
)

# Keys the Dart side may emit that the request model does not declare as
# scores. Keep this list empty unless there is a reason, and state the reason.
_NOT_SCORE_FIELDS = {"timestamp"}


def _dart_source() -> str:
    assert AGGREGATOR.is_file(), f"aggregator not found at {AGGREGATOR}"
    return AGGREGATOR.read_text(encoding="utf-8")


def _build_payload_body(src: str) -> str:
    """The body of `buildPayload()`, where the wire names are written."""
    start = src.index("Map<String, dynamic>? buildPayload()")
    end = src.index("Future<void> flush()", start)
    return src[start:end]


def _emitted_keys(body: str) -> set[str]:
    """Every string literal used as a JSON key in the returned map."""
    # Matches  'motion_score': _round(...)   and   'weapon_label': weapon!.label
    return set(re.findall(r"'([a-z_]+)'\s*:", body))


def test_the_aggregator_source_is_where_we_think_it_is():
    """Guards every other test here from passing on an empty read."""
    keys = _emitted_keys(_build_payload_body(_dart_source()))
    assert len(keys) >= 5, f"only found {keys!r} — has buildPayload moved?"


def test_every_key_the_app_sends_is_a_field_the_backend_declares():
    keys = _emitted_keys(_build_payload_body(_dart_source()))
    declared = set(ModelScoresRequest.model_fields)
    unknown = sorted(keys - declared - _NOT_SCORE_FIELDS - {"timestamp"})
    assert not unknown, (
        "the app sends keys the backend does not declare: "
        + ", ".join(unknown)
        + ". Pydantic ignores unknown fields by default, so these would be "
        "dropped silently and the modality would vanish from fusion."
    )


@pytest.mark.parametrize("field", ["motion_score", "audio_score", "vision_score"])
def test_the_three_modality_names_are_identical_on_both_sides(field):
    """The three that carry the detection signal, named one at a time.

    Parameterised so a failure names the modality that broke rather than
    reporting a set difference.
    """
    keys = _emitted_keys(_build_payload_body(_dart_source()))
    assert field in keys, f"the app no longer sends {field}"
    assert field in ModelScoresRequest.model_fields, f"the backend no longer reads {field}"


def test_the_weapon_label_and_confidence_travel_together():
    keys = _emitted_keys(_build_payload_body(_dart_source()))
    for field in ("weapon_confidence", "weapon_label"):
        assert field in keys, f"the app no longer sends {field}"
        assert field in ModelScoresRequest.model_fields


def test_a_payload_shaped_like_the_app_builds_is_accepted():
    """Parse a realistic body rather than only comparing names."""
    body = {
        "motion_score": 0.93,
        "audio_score": 0.81,
        "vision_score": 0.47,
        "weapon_confidence": 0.47,
        "weapon_label": "a knife",
        "timestamp": "2026-10-11T08:44:00+00:00",
    }
    parsed = ModelScoresRequest(**body)
    assert parsed.motion_score == 0.93
    assert parsed.audio_score == 0.81
    assert parsed.vision_score == 0.47
    assert parsed.weapon_label == "a knife"


def test_a_partial_payload_leaves_the_absent_modalities_as_none():
    """The invariant the whole pipeline rests on: absent is not zero.

    The app omits a stale or retracted signal entirely. The backend must read
    that omission as `None` so `fuse()` renormalises, not as 0.0 — which would
    claim the sensor looked and saw calm.
    """
    parsed = ModelScoresRequest(**{"motion_score": 0.93})
    assert parsed.motion_score == 0.93
    assert parsed.audio_score is None, "a missing audio score must not default to 0.0"
    assert parsed.vision_score is None, "a missing vision score must not default to 0.0"


def test_the_app_never_emits_a_zero_placeholder_for_a_missing_modality():
    """The Dart side must omit, not substitute.

    Pinned here as well as in the Dart suite because this is the contract the
    backend's renormalisation depends on, and it is the regression that once
    made a connected glove suppress a weapon alarm (1.000 -> 0.615).
    """
    body = _build_payload_body(_dart_source())
    for field in ("motion_score", "audio_score", "vision_score"):
        # Each must be written behind a null check, not unconditionally.
        assert re.search(rf"if \(\w+ != null\) '{field}'", body), (
            f"{field} is no longer emitted conditionally — a missing modality "
            "would be sent as a value instead of being omitted"
        )


def test_the_timestamp_the_app_sends_is_parseable_as_utc():
    """The app sends `DateTime.toUtc().toIso8601String()`, which ends in Z."""
    parsed = ModelScoresRequest(**{"motion_score": 0.5,
                                   "timestamp": "2026-10-11T08:44:00.000Z"})
    assert parsed.timestamp is not None
    assert parsed.timestamp.tzinfo is not None, "timestamp lost its offset"
    # And it survives the round trip back out with an explicit offset.
    dumped = json.loads(parsed.model_dump_json())
    assert dumped["timestamp"].endswith("+00:00")
