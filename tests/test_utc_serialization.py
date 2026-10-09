"""Timestamps must leave the server with an explicit UTC offset.

Regression test for a real failure: a journey started at 08:44 UTC was
serialised as `2026-10-09T08:44:00`, and the Flutter app — whose
`DateTime.parse` reads an offset-less string as *local* time — placed it
5h30m in the past on an IST phone and rendered a fresh 15-minute journey as
"5h 18m overdue".

The storage convention (naive, meaning UTC) is fine. Writing it to JSON
without saying so is not.
"""

import json
from datetime import datetime, timezone

import pytest

from fastapi_app import schemas
from fastapi_app.time_utils import as_utc, to_utc_iso, utc_now_iso


def _journey(**overrides):
    base = dict(
        id="j1",
        destination_label="Office",
        expected_duration_minutes=15,
        status="active",
        started_at=datetime(2026, 10, 9, 8, 44),
        expected_arrival_at=datetime(2026, 10, 9, 8, 59),
    )
    base.update(overrides)
    return schemas.JourneyPublic(**base)


def test_journey_timestamps_carry_utc_offset():
    body = json.loads(_journey().model_dump_json())
    assert body["started_at"] == "2026-10-09T08:44:00+00:00"
    assert body["expected_arrival_at"] == "2026-10-09T08:59:00+00:00"


def test_offset_is_present_on_every_journey_timestamp():
    body = json.loads(
        _journey(
            last_check_in_at=datetime(2026, 10, 9, 8, 50),
            ended_at=datetime(2026, 10, 9, 9, 10),
        ).model_dump_json()
    )
    for field in ("started_at", "expected_arrival_at", "last_check_in_at", "ended_at"):
        assert body[field].endswith("+00:00"), f"{field} has no timezone"


def test_optional_timestamps_stay_null():
    body = json.loads(_journey().model_dump_json())
    assert body["last_check_in_at"] is None
    assert body["ended_at"] is None


def test_the_instant_is_not_shifted():
    """Tagging must not move the clock — 08:44 naive is 08:44 UTC."""
    body = json.loads(_journey().model_dump_json())
    parsed = datetime.fromisoformat(body["started_at"])
    assert parsed == datetime(2026, 10, 9, 8, 44, tzinfo=timezone.utc)
    assert parsed.timestamp() == datetime(2026, 10, 9, 8, 44, tzinfo=timezone.utc).timestamp()


def test_already_aware_timestamps_are_preserved():
    aware = datetime(2026, 10, 9, 14, 14, tzinfo=timezone.utc)
    body = json.loads(_journey(started_at=aware).model_dump_json())
    assert body["started_at"] == "2026-10-09T14:14:00+00:00"


def test_non_utc_aware_timestamps_are_converted_not_relabelled():
    ist = timezone(__import__("datetime").timedelta(hours=5, minutes=30))
    body = json.loads(_journey(started_at=datetime(2026, 10, 9, 14, 14, tzinfo=ist)).model_dump_json())
    # 14:14 IST is 08:44 UTC.
    assert body["started_at"] == "2026-10-09T08:44:00+00:00"


def test_python_mode_dump_still_yields_datetimes():
    """Internal callers must be unaffected; only the wire format changed."""
    dumped = _journey().model_dump()
    assert isinstance(dumped["started_at"], datetime)


def _is_utc_tagged(field) -> bool:
    """Whether a Pydantic field will serialise with an explicit offset.

    Pydantic stores the `Annotated` extras differently depending on the shape:
    a bare `UtcDatetime` has its `PlainSerializer` hoisted into `metadata`,
    while `Optional[UtcDatetime]` keeps it inside the union's args.
    """
    if any("PlainSerializer" in str(m) for m in field.metadata):
        return True
    annotation = field.annotation
    return any("PlainSerializer" in str(a) for a in getattr(annotation, "__args__", ()))


def _datetime_fields():
    for name in dir(schemas):
        model = getattr(schemas, name)
        if not (isinstance(model, type) and issubclass(model, schemas.BaseModel)):
            continue
        for field_name, field in model.model_fields.items():
            text = str(field.annotation)
            if "datetime" in text and "date," not in text:
                yield name, field_name, field


def test_no_schema_field_serialises_a_bare_datetime():
    """The bug was never journey-specific — every timestamp field shared it.

    Sweeping all schemas rather than a hand-picked few, so a timestamp added
    later cannot reintroduce the offset-less wire format unnoticed.
    """
    bare = [
        f"{model}.{field}"
        for model, field, spec in _datetime_fields()
        if not _is_utc_tagged(spec)
    ]
    assert not bare, "these serialise without a timezone: " + ", ".join(sorted(bare))


def test_the_sweep_actually_finds_fields():
    """Guards the test above from silently passing on an empty set."""
    assert len(list(_datetime_fields())) >= 15


class TestTimeUtils:
    def test_naive_is_assumed_utc(self):
        assert as_utc(datetime(2026, 10, 9, 8, 44)).tzinfo is timezone.utc

    def test_to_utc_iso_has_offset(self):
        assert to_utc_iso(datetime(2026, 10, 9, 8, 44)) == "2026-10-09T08:44:00+00:00"

    def test_to_utc_iso_passes_none_through(self):
        assert to_utc_iso(None) is None

    def test_utc_now_iso_is_parseable_and_aware(self):
        parsed = datetime.fromisoformat(utc_now_iso())
        assert parsed.tzinfo is not None
