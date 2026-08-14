from collections import Counter
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.models import Incident
from fastapi_app.schemas import UserPublic
from fastapi_app.security import get_current_user

router = APIRouter(prefix="/api/v1/dashboard", tags=["dashboard"])


@router.get("/summary")
async def get_dashboard_summary(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Real aggregation over this user's own incidents only — no synthetic
    trend/heatmap data. Fields with nothing to aggregate come back empty
    rather than fabricated (e.g. no incidents yet -> empty breakdown, not a
    zeroed-out fake chart).
    """
    rows = (
        (await session.execute(select(Incident).where(Incident.user_id == current_user.id)))
        .scalars()
        .all()
    )

    total_incidents = len(rows)

    threat_level_breakdown = Counter(row.threat_level or "unknown" for row in rows)

    window_start = datetime.now(timezone.utc).date() - timedelta(days=6)
    daily_counts: dict[str, int] = {
        (window_start + timedelta(days=offset)).isoformat(): 0 for offset in range(7)
    }
    for row in rows:
        created = row.created_at
        if created is None:
            continue
        created_date = created.date() if hasattr(created, "date") else created
        key = created_date.isoformat()
        if key in daily_counts:
            daily_counts[key] += 1

    most_recent = max(rows, key=lambda r: r.created_at, default=None)

    return {
        "total_incidents": total_incidents,
        "threat_level_breakdown": dict(threat_level_breakdown),
        "incidents_last_7_days": [{"date": date, "count": count} for date, count in daily_counts.items()],
        "most_recent_incident": (
            {
                "id": most_recent.id,
                "title": most_recent.title,
                "threat_level": most_recent.threat_level,
                "created_at": most_recent.created_at,
            }
            if most_recent
            else None
        ),
    }
