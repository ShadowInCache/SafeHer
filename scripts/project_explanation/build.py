"""Assemble the SafeHer technical project description PDF.

Run from the repository root so the figure paths resolve:
    python <scratchpad>/pdf/build.py docs/SafeHer_Project_Explanation.pdf
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from reportlab.platypus import BaseDocTemplate, Frame, PageTemplate

from content_a import part_a
from content_b import part_b
from style import BM, LM, PAGE, PH, PW, RM, TM, on_any


def build(out_path):
    doc = BaseDocTemplate(
        out_path, pagesize=PAGE,
        leftMargin=LM, rightMargin=RM, topMargin=TM, bottomMargin=BM,
        title="SafeHer - Technical Project Description",
        author="Akshay",
        subject="Multi-modal wearable threat detection: system description and "
                "measured evidence",
        creator="SafeHer project",
    )
    frame = Frame(LM, BM, PW - LM - RM, PH - TM - BM, id="main",
                  leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    doc.addPageTemplates([
        PageTemplate(id="main", frames=[frame], onPage=on_any),
    ])

    story = part_a() + part_b()
    doc.build(story)
    return doc.page


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "SafeHer_Project_Explanation.pdf"
    pages = build(out)
    print(f"wrote {out}: {pages} pages")
