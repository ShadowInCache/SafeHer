"""Shared page furniture and styles for the SafeHer project description PDF."""

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm

PAGE = A4
PW, PH = PAGE
LM = RM = 20 * mm
TM = 20 * mm
BM = 18 * mm
CONTENT_W = PW - LM - RM

INK = colors.HexColor("#17171F")
BODY = colors.HexColor("#2C2C38")
MUTED = colors.HexColor("#6B6B7B")
ACCENT = colors.HexColor("#B8415C")
ACCENT_SOFT = colors.HexColor("#FAF0F2")
RULE = colors.HexColor("#D5D5DE")
RULE_LIGHT = colors.HexColor("#E8E8EE")
HEAD_BG = colors.HexColor("#F3F3F7")
NOTE_BG = colors.HexColor("#F4F6FA")
NOTE_EDGE = colors.HexColor("#C3CEE0")
GOOD = colors.HexColor("#2E6E4E")
BAD = colors.HexColor("#A33A28")

_ss = getSampleStyleSheet()


def _s(name, **kw):
    base = kw.pop("parent", _ss["Normal"])
    return ParagraphStyle(name, parent=base, **kw)


S = {}

S["title"] = _s(
    "title", fontName="Helvetica-Bold", fontSize=30, leading=35,
    textColor=INK, spaceAfter=0, alignment=TA_LEFT,
)
S["subtitle"] = _s(
    "subtitle", fontName="Helvetica", fontSize=13.5, leading=19,
    textColor=MUTED, spaceBefore=8,
)
S["covermeta"] = _s(
    "covermeta", fontName="Helvetica", fontSize=9.5, leading=15, textColor=MUTED,
)
S["coverlabel"] = _s(
    "coverlabel", fontName="Helvetica-Bold", fontSize=8, leading=13,
    textColor=ACCENT, spaceAfter=2,
)

S["h1"] = _s(
    "h1", fontName="Helvetica-Bold", fontSize=17, leading=21,
    textColor=INK, spaceBefore=0, spaceAfter=3, keepWithNext=1,
)
S["h1num"] = _s(
    "h1num", fontName="Helvetica-Bold", fontSize=8.5, leading=11,
    textColor=ACCENT, spaceAfter=3,
)
S["h2"] = _s(
    "h2", fontName="Helvetica-Bold", fontSize=11.5, leading=15,
    textColor=INK, spaceBefore=15, spaceAfter=5, keepWithNext=1,
)
S["h3"] = _s(
    "h3", fontName="Helvetica-BoldOblique", fontSize=9.8, leading=13,
    textColor=BODY, spaceBefore=11, spaceAfter=3, keepWithNext=1,
)

S["body"] = _s(
    "body", fontName="Helvetica", fontSize=9.6, leading=14.6,
    textColor=BODY, alignment=TA_JUSTIFY, spaceAfter=8,
)
S["lead"] = _s(
    "lead", fontName="Helvetica", fontSize=11, leading=17,
    textColor=BODY, alignment=TA_LEFT, spaceAfter=10,
)
S["bullet"] = _s(
    "bullet", parent=S["body"], leftIndent=11, bulletIndent=1,
    spaceAfter=4, alignment=TA_LEFT,
)
S["caption"] = _s(
    "caption", fontName="Helvetica", fontSize=8, leading=11.5,
    textColor=MUTED, spaceBefore=5, spaceAfter=12, alignment=TA_LEFT,
)
S["figlabel"] = _s(
    "figlabel", fontName="Helvetica-Bold", fontSize=8, leading=11.5,
    textColor=ACCENT,
)
S["note"] = _s(
    "note", fontName="Helvetica", fontSize=9, leading=13.6,
    textColor=BODY, alignment=TA_LEFT, spaceAfter=0,
)
S["notehead"] = _s(
    "notehead", fontName="Helvetica-Bold", fontSize=8, leading=12,
    textColor=INK, spaceAfter=3,
)
S["cell"] = _s(
    "cell", fontName="Helvetica", fontSize=8.3, leading=11.4, textColor=BODY,
)
S["cellb"] = _s(
    "cellb", fontName="Helvetica-Bold", fontSize=8.3, leading=11.4, textColor=INK,
)
S["cellhead"] = _s(
    "cellhead", fontName="Helvetica-Bold", fontSize=7.6, leading=10.5, textColor=INK,
)
S["mono"] = _s(
    "mono", fontName="Courier", fontSize=8.2, leading=12.4, textColor=BODY,
)
S["toc1"] = _s(
    "toc1", fontName="Helvetica-Bold", fontSize=9.5, leading=17, textColor=INK,
)
S["toc2"] = _s(
    "toc2", fontName="Helvetica", fontSize=9.2, leading=15, textColor=BODY,
    leftIndent=14,
)
S["center"] = _s("center", parent=S["body"], alignment=TA_CENTER)


def on_page(canvas, doc):
    """Footer rule, running title and page number."""
    canvas.saveState()
    if doc.page > 1:
        canvas.setStrokeColor(RULE_LIGHT)
        canvas.setLineWidth(0.5)
        canvas.line(LM, BM - 5, PW - RM, BM - 5)

        canvas.setFont("Helvetica", 7.2)
        canvas.setFillColor(MUTED)
        canvas.drawString(
            LM, BM - 13,
            "SafeHer — Technical Project Description · Revision 2026-11-04",
        )
        canvas.setFont("Helvetica-Bold", 7.6)
        canvas.setFillColor(INK)
        canvas.drawRightString(PW - RM, BM - 13, str(doc.page))
    canvas.restoreState()


def on_cover(canvas, doc):
    """Cover page: accent band at the head, ink band at the foot."""
    canvas.saveState()
    canvas.setFillColor(ACCENT)
    canvas.rect(0, PH - 10 * mm, PW, 10 * mm, stroke=0, fill=1)
    canvas.setFillColor(INK)
    canvas.rect(0, 0, PW, 4 * mm, stroke=0, fill=1)
    canvas.restoreState()


def on_any(canvas, doc):
    """Page 1 gets the cover furniture; every later page gets the footer."""
    if doc.page == 1:
        on_cover(canvas, doc)
    else:
        on_page(canvas, doc)
