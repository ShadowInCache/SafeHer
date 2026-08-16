"""Forensic incident report as PDF — SRS FR-RPT-03.

"Forensic-grade" is doing the work in that requirement. A PDF that merely
restates what the app shows is a printout; what makes a report usable as
evidence is that a reader can later prove the file they hold is the one that
was generated, and that the recording it describes has not been swapped.

So the report carries a **chain of custody**: the SHA-256 of every evidence
file, plus a document hash over the report's own facts. Anyone can re-hash
the recording they were given and compare. Nothing here is a signature — it
proves integrity against accident and casual tampering, not against someone
who can regenerate the whole report. Said plainly on the page rather than
implied, because overstating what a hash proves is worse than omitting it.
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Optional, Sequence

from fpdf import FPDF

VIOLET = (124, 58, 237)
INK = (24, 24, 27)
MUTED = (110, 110, 120)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _grouped(digest: str) -> str:
    """Hex in 8-char groups — a hash nobody can read off the page cannot be
    compared by hand, which is the only way most readers will check it."""
    return " ".join(digest[i : i + 8] for i in range(0, len(digest), 8))


class _Report(FPDF):
    def header(self) -> None:
        self.set_font("Helvetica", "B", 16)
        self.set_text_color(*VIOLET)
        self.cell(0, 10, "SafeHer Incident Report", new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(*VIOLET)
        self.line(self.l_margin, self.get_y(), self.w - self.r_margin, self.get_y())
        self.ln(4)

    def footer(self) -> None:
        self.set_y(-15)
        self.set_font("Helvetica", "", 8)
        self.set_text_color(*MUTED)
        self.cell(0, 10, f"Page {self.page_no()} of {{nb}}", align="C")


def build_incident_pdf(
    *,
    incident_title: str,
    incident_description: Optional[str],
    threat_level: Optional[str],
    occurred_at: datetime,
    reported_by: str,
    latitude: Optional[float],
    longitude: Optional[float],
    evidence: Sequence[tuple[str, str, bytes]],
    contacts_notified: Optional[int] = None,
) -> bytes:
    """Renders the report.

    [evidence] is `(media_id, media_type, plaintext_bytes)`. The bytes are
    hashed and discarded — the recording itself never goes into the PDF,
    both because it would not survive the format and because a report is
    routinely forwarded to people who should see the summary rather than
    hear the audio.
    """
    pdf = _Report()
    pdf.set_auto_page_break(auto=True, margin=18)
    pdf.alias_nb_pages()
    pdf.add_page()

    def heading(text: str) -> None:
        pdf.ln(3)
        pdf.set_font("Helvetica", "B", 11)
        pdf.set_text_color(*VIOLET)
        pdf.cell(0, 7, text.upper(), new_x="LMARGIN", new_y="NEXT")
        pdf.set_text_color(*INK)

    def field(label: str, value: str) -> None:
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(42, 6, label)
        pdf.set_font("Helvetica", "", 10)
        pdf.multi_cell(0, 6, value, new_x="LMARGIN", new_y="NEXT")

    heading("Incident")
    field("Title", incident_title)
    field("Severity", (threat_level or "not recorded").upper())
    field("Occurred", occurred_at.strftime("%d %B %Y at %H:%M UTC"))
    field("Reported by", reported_by)
    if contacts_notified is not None:
        field("Contacts alerted", str(contacts_notified))
    if incident_description:
        field("Summary", incident_description)

    heading("Location")
    if latitude is not None and longitude is not None:
        field("Coordinates", f"{latitude:.6f}, {longitude:.6f}")
        field("Map", f"https://maps.google.com/?q={latitude:.6f},{longitude:.6f}")
    else:
        # Stated rather than left blank: "no fix was available" and "nobody
        # filled this in" are different facts about an incident.
        field("Coordinates", "No location was captured for this incident.")

    heading("Evidence")
    if not evidence:
        field("Recordings", "No evidence was captured for this incident.")
    else:
        for index, (media_id, media_type, blob) in enumerate(evidence, start=1):
            pdf.set_font("Helvetica", "B", 10)
            pdf.cell(0, 6, f"{index}. {media_type} ({len(blob):,} bytes)", new_x="LMARGIN", new_y="NEXT")
            pdf.set_font("Helvetica", "", 9)
            pdf.set_text_color(*MUTED)
            pdf.multi_cell(0, 5, f"ID       {media_id}", new_x="LMARGIN", new_y="NEXT")
            pdf.multi_cell(0, 5, f"SHA-256  {_grouped(sha256_hex(blob))}", new_x="LMARGIN", new_y="NEXT")
            pdf.set_text_color(*INK)
            pdf.ln(1)

    generated_at = datetime.now(timezone.utc)
    heading("Chain of custody")
    pdf.set_font("Helvetica", "", 9)
    pdf.multi_cell(
        0,
        5,
        "Each recording above is listed with the SHA-256 of the exact bytes "
        "held by SafeHer at the time this report was generated. Re-hashing a "
        "copy you have been given and comparing it with the value above shows "
        "whether that copy is unaltered.\n\n"
        "This is an integrity check, not a signature: it demonstrates that a "
        "file matches this report, and does not by itself prove who created "
        "either.",
        new_x="LMARGIN",
        new_y="NEXT",
    )
    pdf.ln(2)

    # A hash over the report's own facts, so the document can be checked as
    # a whole and not only recording by recording.
    document_digest = sha256_hex(
        "|".join(
            [
                incident_title,
                threat_level or "",
                occurred_at.isoformat(),
                reported_by,
                f"{latitude}",
                f"{longitude}",
                *[sha256_hex(blob) for _, _, blob in evidence],
            ]
        ).encode("utf-8")
    )
    field("Generated", generated_at.strftime("%d %B %Y at %H:%M UTC"))
    pdf.set_font("Helvetica", "B", 9)
    pdf.cell(42, 6, "Document hash")
    pdf.set_font("Courier", "", 8)
    pdf.multi_cell(0, 6, _grouped(document_digest), new_x="LMARGIN", new_y="NEXT")

    return bytes(pdf.output())
