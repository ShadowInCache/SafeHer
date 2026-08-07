# Archived Documentation

These documents are preserved for historical context, not as current truth. They were
generated between 2026-03-23 and 2026-04-03 against an earlier state of this codebase
(a Flask-based gateway architecture, before the FastAPI rewrite under `fastapi_app/`).

**Do not use these as setup or API instructions.** See the root-level `README.md`,
`ARCHITECTURE.md`, `SETUP.md`, and `API.md` for the current, verified state of the
project. Where these archived documents contain product framing, known limitations, or
security notes that still held up during the 2026-08-08 audit, that content has been
carried forward into the new docs.

| File | What it was |
|---|---|
| `README_ORIGINAL.md` | The repo's previous root README. Large sections describe an aspirational architecture (separate `backend/`/`frontend/` dirs, Flask gateway on port 5000, RabbitMQ, TimescaleDB, Kubernetes) that does not match the actual codebase, alongside some accurate April 2026 runtime notes about the FastAPI migration. |
| `BACKEND_INTEGRATION.md` | REST/WebSocket API reference for the pre-FastAPI event-processor design. |
| `COMPREHENSIVE_PROJECT_REPORT.md` | A full self-generated project audit from 2026-03-29. |
| `OPTIMIZATION_REPORT.md` | Performance/optimization notes from the same audit pass. |
| `PROJECT_STATUS.md` | A point-in-time completeness assessment (~82% complete, 40% test coverage). |
| `PROJECT_STRUCTURE_OLD.md` | An earlier folder-structure explanation, superseded by the new `PROJECT_STRUCTURE.md`. |
| `QUICK_REFERENCE.md` | A command cheat-sheet for the old Flask/microservices workflow. |
| `TECHNICAL_INVENTORY.md` | An inventory of components as they existed in March 2026. |
| `_audit_scan_subset.json` | Raw scan data backing the above reports. |
| `QUICKSTART.py.txt` | A printable onboarding script (originally `QUICKSTART.py` at repo root) documenting the old `manage.py start-gateway` Flask flow. Renamed `.txt` since it's no longer meant to be executed. |
