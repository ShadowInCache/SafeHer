"""Keeps docs/TRACEABILITY.md honest against SRS.md and the filesystem.

"Verify it against the SRS" was, until this landed, something only a person
reading both documents could do — and a first attempt at auditing it
automatically reported 20 of 37 requirements as unimplemented when almost
all of them were built and simply never linked to the requirement they
satisfy.

These tests make the mapping enforceable: a requirement cannot quietly go
missing from the map, and the map cannot quietly point at a file that no
longer exists. Neither failure is hypothetical — the second is what happens
every time a file is renamed.
"""

from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRS = ROOT / "SRS.md"
MAP = ROOT / "docs" / "TRACEABILITY.md"

# "blocked" earns its place separately from "partial". Partial means the
# feature works with a stated limit; blocked means the code is correct and the
# environment refuses to run it -- Render's free tier blocks outbound SMTP, so
# emergency email fails on the deployed host while passing every test. Calling
# that "partial" would let an alert channel that reaches nobody read as
# working-with-caveats on a scan of the matrix.
VALID_STATUSES = {"done", "partial", "blocked", "not built"}


def srs_requirements() -> list[tuple[str, str]]:
    """`(id, priority)` for every functional requirement table row."""
    text = SRS.read_text(encoding="utf-8", errors="replace")
    return re.findall(r"\|\s*(FR-[A-Z]+-\d+)\s*\|[^|]+\|\s*(MUST|SHOULD)\s*\|", text)


def mapped_requirements() -> dict[str, tuple[str, str]]:
    """`id -> (status, implementation cell)`."""
    text = MAP.read_text(encoding="utf-8", errors="replace")
    rows = re.findall(r"\|\s*(FR-[A-Z]+-\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|", text)
    return {fid: (status, impl) for fid, status, impl in rows}


class TestTraceability(unittest.TestCase):
    def test_the_srs_actually_parses(self):
        # Guards the guard: a regex that silently matches nothing would make
        # every test below pass vacuously.
        self.assertGreaterEqual(len(srs_requirements()), 30)
        self.assertGreaterEqual(len(mapped_requirements()), 30)

    def test_every_requirement_is_accounted_for(self):
        missing = [fid for fid, _ in srs_requirements() if fid not in mapped_requirements()]

        self.assertEqual(
            missing,
            [],
            "requirements in SRS.md with no row in docs/TRACEABILITY.md: "
            "add one, marking it 'not built' if that is the truth",
        )

    def test_the_map_invents_no_requirements(self):
        known = {fid for fid, _ in srs_requirements()}
        invented = [fid for fid in mapped_requirements() if fid not in known]

        self.assertEqual(invented, [], "rows in TRACEABILITY.md that SRS.md does not define")

    def test_statuses_are_from_the_fixed_set(self):
        bad = {
            fid: status
            for fid, (status, _) in mapped_requirements().items()
            if status.strip("* ").lower() not in VALID_STATUSES
        }

        self.assertEqual(bad, {}, f"status must be one of {sorted(VALID_STATUSES)}")

    def test_every_referenced_file_exists(self):
        # The failure this catches is a rename: the map keeps pointing at the
        # old path and quietly stops meaning anything.
        missing: list[str] = []
        for fid, (status, impl) in mapped_requirements().items():
            for path in re.findall(r"`([^`]+)`", impl):
                if "/" not in path:
                    continue
                if not (ROOT / path).exists():
                    missing.append(f"{fid} -> {path}")

        self.assertEqual(missing, [], "TRACEABILITY.md points at files that do not exist")

    def test_built_requirements_name_an_implementation(self):
        unsupported = [
            fid
            for fid, (status, impl) in mapped_requirements().items()
            if status.strip("* ").lower() in {"done", "partial"} and "`" not in impl
        ]

        self.assertEqual(
            unsupported,
            [],
            "a requirement claimed as done or partial must cite the code that implements it",
        )

    def test_unbuilt_requirements_do_not_claim_an_implementation(self):
        # The dangerous direction: a file path next to "not built" reads as
        # progress that does not exist.
        contradictory = [
            fid
            for fid, (status, impl) in mapped_requirements().items()
            if status.strip("* ").lower() == "not built" and re.search(r"`[^`]+/", impl)
        ]

        self.assertEqual(contradictory, [])


if __name__ == "__main__":
    unittest.main()
