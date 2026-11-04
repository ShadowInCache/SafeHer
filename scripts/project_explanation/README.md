# Project explanation PDF

Regenerates `docs/SafeHer_Project_Explanation.pdf` — the technical project
description that accompanies the evaluation report.

```
python scripts/project_explanation/build.py docs/SafeHer_Project_Explanation.pdf
```

Run it from the repository root: the figure paths in `content_b.py` resolve
against the working directory, and the figures come from
`docs/assets/evaluation/`, which `scripts/make_charts.py` and
`scripts/make_evidence_figures.py` produce.

Every number in the document is copied from `docs/model_evaluation_results.json`
or from a named source file in this repository. Nothing in it is computed here,
so this script cannot invent a figure — but it also cannot notice when one goes
stale. If the evaluation data changes, the prose has to be changed by hand.

| File | Holds |
|---|---|
| `build.py` | Document assembly and page setup |
| `style.py` | Palette, paragraph styles, page furniture |
| `blocks.py` | Headings, tables, callouts, figures, flow diagrams |
| `content_a.py` | Cover, contents, sections 1–6 |
| `content_b.py` | Sections 7–15 |

Requires `reportlab` and `Pillow`, both already in the project's Python
environment.
