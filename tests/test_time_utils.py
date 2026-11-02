"""Pin the UTC conventions, and the one that was silently wrong.

## The defect these tests exist to prevent

`fastapi_app/routers/media.py` signed Cloudinary direct uploads with

    timestamp = int(datetime.utcnow().timestamp())

which reads correct and is not. `datetime.utcnow()` returns a *naive* datetime
holding the UTC wall clock, and `.timestamp()` interprets a naive datetime as
**local** time. The result is therefore wrong by the host's UTC offset: measured
on the development machine (IST, +05:30) it came out 19,800 seconds in the past.

Cloudinary rejects a signed upload whose timestamp is more than about an hour
from its own clock. So evidence upload signing failed on any server not running
in UTC and worked perfectly on one that was -- the shape of bug that passes
every test on CI and breaks in the one place it matters.

## Why there are two kinds of test here

The direct assertion (`utc_epoch_seconds` agrees with `time.time()`) is the
honest statement of the requirement, but it is **vacuous on a UTC host**: the
broken expression and the correct one return the same number when the offset is
zero, so a UTC CI box cannot catch a regression.

The source guard is therefore the one with teeth. It asserts the broken call
does not reappear anywhere in the backend, which is true or false independently
of what timezone the test runs in. Keeping only the first test would be the
same mistake this project has now found several times: a check that passes on
the healthy case and cannot fail on the broken one.
"""

from __future__ import annotations

import re
import time
import warnings
from datetime import datetime, timezone
from pathlib import Path

import pytest

from fastapi_app.time_utils import (
    as_utc,
    naive_utc_now,
    to_utc_iso,
    utc_epoch_seconds,
)

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "fastapi_app"

# The guard covers the tests too: a fixture that sets up a naive timestamp with
# the deprecated call still breaks when it is removed, and the five that existed
# were the only remaining source of DeprecationWarning in the suite.
GUARDED_TREES = (BACKEND, ROOT / "tests")

# `time_utils` names the call in the docstrings explaining why not to use it, and
# this file calls it deliberately to demonstrate the bug.
GUARD_EXEMPT = {"time_utils.py", "test_time_utils.py"}

# `datetime.utcnow(` -- the call, not the word in prose. Matches `datetime.utcnow()`
# and the aliased `dt.utcnow()` form.
UTCNOW_CALL = re.compile(r"\b(?:datetime|dt)\.utcnow\s*\(")


def _host_utc_offset_seconds() -> float:
    return datetime.now().astimezone().utcoffset().total_seconds()


def test_utc_epoch_seconds_is_real_epoch_time():
    """The requirement, stated directly. Vacuous on a UTC host -- see module docstring."""
    assert abs(utc_epoch_seconds() - time.time()) < 2, (
        "utc_epoch_seconds() disagrees with the system clock, which means it is "
        "being built from a naive datetime again"
    )


def test_the_broken_pattern_really_was_broken():
    """Demonstrate the bug, so the guard below is not protecting against nothing.

    Skips on a UTC host, where the two expressions coincide and there is
    nothing to demonstrate. That the test can go quiet is the whole reason the
    source guard exists.
    """
    offset = _host_utc_offset_seconds()
    if offset == 0:
        pytest.skip("host is on UTC, where the broken expression coincides")

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        broken = datetime.utcnow().timestamp()

    error = broken - time.time()
    assert abs(error + offset) < 2, (
        f"expected the naive-datetime route to be wrong by the host offset "
        f"({offset:.0f}s); it was off by {error:.0f}s"
    )
    # An hour is roughly Cloudinary's tolerance for a signed request.
    assert abs(error) > 60, (
        "the broken pattern is not measurably wrong on this host, so this test "
        "is not demonstrating anything"
    )


def test_no_backend_code_calls_utcnow():
    """The guard with teeth: timezone-independent, so CI can enforce it.

    `datetime.utcnow()` is deprecated and scheduled for removal, and every use
    of it in this backend was a naive value that meant UTC. The replacement is
    `time_utils.naive_utc_now()` for storage and `utc_epoch_seconds()` for
    epoch arithmetic. `time_utils.py` itself is allowed to name the call in the
    docstrings that explain why not to use it.
    """
    offenders = []
    for tree in GUARDED_TREES:
        for path in sorted(tree.rglob("*.py")):
            if path.name in GUARD_EXEMPT:
                continue
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if UTCNOW_CALL.search(line) and not line.lstrip().startswith("#"):
                    offenders.append(
                        f"{path.relative_to(ROOT).as_posix()}:{n}: {line.strip()}")

    assert not offenders, (
        "datetime.utcnow() is deprecated, and building epoch seconds from it is "
        "wrong by the host's UTC offset. Use time_utils.naive_utc_now() for "
        "storage or time_utils.utc_epoch_seconds() for epoch arithmetic:\n  "
        + "\n  ".join(offenders)
    )


def test_naive_utc_now_matches_the_storage_convention():
    """Columns are naive and mean UTC; a tz-aware value here would poison comparisons."""
    now = naive_utc_now()
    assert now.tzinfo is None, (
        "naive_utc_now() returned an aware datetime; comparing that against a "
        "naive column raises TypeError at runtime"
    )
    # It must be UTC wall-clock, not local wall-clock with the offset dropped.
    delta = abs((now - datetime.now(timezone.utc).replace(tzinfo=None)).total_seconds())
    assert delta < 2, f"naive_utc_now() is not UTC wall-clock; off by {delta:.0f}s"


def test_only_one_definition_of_naive_utc_now_remains():
    """Five modules each defined this privately, two of them on the deprecated call.

    One definition is harder to get inconsistently wrong than five, and the
    inconsistency was real: `models._utcnow` used `datetime.utcnow()` while
    `repositories.safety._naive_utcnow` already used the correct form.
    """
    definitions = []
    for path in sorted(BACKEND.rglob("*.py")):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if re.match(r"\s*def _?(naive_)?utc(now|_now)\s*\(", line):
                # Deliberately no line number: pinning one makes the test fail
                # on any edit above it, which teaches people to ignore it.
                definitions.append(path.relative_to(BACKEND.parent).as_posix())

    assert definitions == ["fastapi_app/time_utils.py"], (
        f"expected exactly one definition, in time_utils.py; found {definitions}. "
        f"Import `naive_utc_now` rather than redefining it."
    )


def test_outbound_timestamps_carry_an_offset():
    """The bug `time_utils` was written for: a naive ISO string reads as local time."""
    naive = datetime(2026, 10, 9, 8, 44, 0)
    rendered = to_utc_iso(naive)
    assert rendered is not None and rendered.endswith("+00:00"), (
        f"{rendered!r} has no offset; Dart's DateTime.parse and JavaScript's "
        f"Date both read that as local time"
    )
    assert to_utc_iso(None) is None
    assert as_utc(naive).tzinfo is timezone.utc
