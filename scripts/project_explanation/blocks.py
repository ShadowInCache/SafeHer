"""Flowable builders: headings, tables, callouts, figures."""

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.platypus import (
    CondPageBreak, HRFlowable, Image, KeepTogether, ListFlowable, ListItem,
    Paragraph, Spacer, Table, TableStyle,
)

from style import (
    ACCENT, ACCENT_SOFT, BODY, CONTENT_W, HEAD_BG, INK, MUTED, NOTE_BG,
    NOTE_EDGE, RULE, RULE_LIGHT, S,
)


def P(text, style="body"):
    return Paragraph(text, S[style])


def SP(h=6):
    return Spacer(1, h)


def H1(number, text):
    # Start a fresh page only when too little room is left for the section to
    # begin properly; otherwise sections flow, which avoids half-empty pages.
    return [
        Spacer(1, 16),
        CondPageBreak(95 * mm),
        Paragraph(f"SECTION {number}", S["h1num"]),
        Paragraph(text, S["h1"]),
        HRFlowable(width="100%", thickness=1.2, color=ACCENT,
                   spaceBefore=5, spaceAfter=12),
    ]


def H2(text):
    return Paragraph(text, S["h2"])


def H3(text):
    return Paragraph(text, S["h3"])


def BULLETS(items, style="bullet"):
    return ListFlowable(
        [ListItem(Paragraph(i, S[style]), leftIndent=11, value="circle")
         for i in items],
        bulletType="bullet", bulletFontSize=4.5, bulletOffsetY=-2.5,
        bulletColor=ACCENT, leftIndent=9, spaceAfter=8,
    )


def NUMBERED(items):
    return ListFlowable(
        [ListItem(Paragraph(i, S["bullet"]), leftIndent=14) for i in items],
        bulletType="1", bulletFontName="Helvetica-Bold", bulletFontSize=8.6,
        bulletColor=ACCENT, leftIndent=13, spaceAfter=8,
    )


def _c(text, style="cell"):
    return Paragraph(str(text), S[style])


def TBL(header, rows, widths, aligns=None, head_align=None, zebra=True,
        font_rows=None):
    """A table with a tinted header row, hairline rules and optional zebra."""
    total = sum(widths)
    cols = [w / total * CONTENT_W for w in widths]
    aligns = aligns or ["LEFT"] * len(header)
    head_align = head_align or aligns

    data = [[_c(h, "cellhead") for h in header]]
    for r in rows:
        data.append([
            _c(cell, (font_rows or {}).get(i, "cell")) if not hasattr(cell, "wrap")
            else cell
            for i, cell in enumerate(r)
        ])

    cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("LINEBELOW", (0, 0), (-1, 0), 0.9, RULE),
        ("LINEABOVE", (0, 0), (-1, 0), 0.9, RULE),
        ("LINEBELOW", (0, -1), (-1, -1), 0.9, RULE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ]
    for i, a in enumerate(head_align):
        cmds.append(("ALIGN", (i, 0), (i, 0), a))
    for i, a in enumerate(aligns):
        cmds.append(("ALIGN", (i, 1), (i, -1), a))
    for r in range(1, len(data) - 1):
        cmds.append(("LINEBELOW", (0, r), (-1, r), 0.4, RULE_LIGHT))
    if zebra:
        for r in range(1, len(data)):
            if r % 2 == 0:
                cmds.append(("BACKGROUND", (0, r), (-1, r),
                             colors.HexColor("#FAFAFC")))

    t = Table(data, colWidths=cols, repeatRows=1, hAlign="LEFT")
    t.setStyle(TableStyle(cmds))
    return t


def NOTE(heading, body, tone="info"):
    """A boxed aside. tone: info (blue-grey) or caution (rose)."""
    bg, edge = (NOTE_BG, NOTE_EDGE) if tone == "info" else (ACCENT_SOFT, ACCENT)
    inner = [Paragraph(heading.upper(), S["notehead"])]
    if isinstance(body, str):
        body = [body]
    for i, b in enumerate(body):
        inner.append(Paragraph(b, S["note"]))
        if i < len(body) - 1:
            inner.append(Spacer(1, 6))
    t = Table([[inner]], colWidths=[CONTENT_W], hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LINEBEFORE", (0, 0), (0, -1), 2.2, edge),
        ("TOPPADDING", (0, 0), (-1, -1), 9),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
        ("LEFTPADDING", (0, 0), (-1, -1), 11),
        ("RIGHTPADDING", (0, 0), (-1, -1), 11),
    ]))
    return KeepTogether([Spacer(1, 4), t, Spacer(1, 12)])


def FIG(path, label, caption, max_w=CONTENT_W, max_h=165 * mm):
    """Embed an image scaled to fit, with a labelled caption underneath."""
    with PILImage.open(path) as im:
        w, h = im.size
    scale = min(max_w / w, max_h / h)
    img = Image(path, width=w * scale, height=h * scale)
    img.hAlign = "CENTER"
    cap = Table(
        [[Paragraph(label, S["figlabel"]), Paragraph(caption, S["caption"])]],
        colWidths=[22 * mm, CONTENT_W - 22 * mm], hAlign="LEFT",
    )
    cap.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    return KeepTogether([
        Spacer(1, 4), img,
        HRFlowable(width="100%", thickness=0.5, color=RULE_LIGHT,
                   spaceBefore=7, spaceAfter=0),
        cap, Spacer(1, 14),
    ])


def KV(pairs, label_w=52):
    """A borderless label/value list, for specification blocks."""
    data = [[_c(k, "cellb"), _c(v)] for k, v in pairs]
    cols = [label_w / 100 * CONTENT_W, (100 - label_w) / 100 * CONTENT_W]
    t = Table(data, colWidths=cols, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 3.5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3.5),
        ("LEFTPADDING", (0, 0), (0, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("LINEBELOW", (0, 0), (-1, -2), 0.4, RULE_LIGHT),
    ]))
    return t


def FLOW(stages, width=CONTENT_W):
    """A horizontal chain of boxes with arrows between them."""
    cells, cols = [], []
    arrow_w = 7 * mm
    box_w = (width - arrow_w * (len(stages) - 1)) / len(stages)
    for i, s in enumerate(stages):
        cells.append(Paragraph(s, S["center"]))
        cols.append(box_w)
        if i < len(stages) - 1:
            cells.append(Paragraph(
                '<font color="#B8415C" size="12"><b>&#187;</b></font>',
                S["center"]))
            cols.append(arrow_w)
    t = Table([cells], colWidths=cols, hAlign="LEFT")
    style = [
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]
    for i in range(0, len(cells), 2):
        style += [
            ("BACKGROUND", (i, 0), (i, 0), HEAD_BG),
            ("BOX", (i, 0), (i, 0), 0.6, RULE),
        ]
    t.setStyle(TableStyle(style))
    return KeepTogether([Spacer(1, 3), t, Spacer(1, 12)])
