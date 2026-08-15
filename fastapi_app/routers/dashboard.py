from collections import Counter
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app.db import get_session
from fastapi_app.models import Device, Incident, Location
from fastapi_app.schemas import UserPublic
from fastapi_app.security import get_current_user

router = APIRouter(prefix="/api/v1/dashboard", tags=["dashboard"])


def _date_of(row) -> date | None:
    """Calendar day a row was created on, tolerating both DateTime and Date
    columns (SQLite hands back either depending on how the value was bound).
    """
    created = getattr(row, "created_at", None)
    if created is None:
        return None
    return created.date() if hasattr(created, "date") else created


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
        created_date = _date_of(row)
        if created_date is None:
            continue
        key = created_date.isoformat()
        if key in daily_counts:
            daily_counts[key] += 1

    most_recent = max(rows, key=lambda r: r.created_at, default=None)

    return {
        "total_incidents": total_incidents,
        "threat_level_breakdown": dict(threat_level_breakdown),
        "incidents_last_7_days": [
            {"date": day, "count": count} for day, count in daily_counts.items()
        ],
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


# --------------------------------------------------------------------------
# Analytics — backs SRS Part 3, SCREEN 9 (`/dashboard`).
#
# Same rule as /summary: every number is aggregated from this user's own
# rows. Where the schema has no history to aggregate (device battery is a
# single current reading, not a time series) the response says so explicitly
# rather than inventing a trend line.
# --------------------------------------------------------------------------

# Roughly 1.1 km at the equator. Coarse on purpose: a heat cell must never
# resolve to a single doorstep, because these are the places where a woman
# was in danger.
HEATMAP_CELL_DEGREES = 0.01

TREND_WINDOW_DAYS = 30
THREAT_BY_DAY_WINDOW_DAYS = 14
SAFETY_SCORE_WINDOW_DAYS = 7

# Penalty per incident when scoring the week. An unlabelled incident counts
# as "medium" rather than free, so a missing label can never flatter the
# score.
_THREAT_WEIGHTS = {"critical": 30, "high": 20, "medium": 10, "low": 4}
_DEFAULT_THREAT_WEIGHT = 10


def _snap(value: float) -> float:
    """Snap a coordinate to the south-west corner of its heat cell."""
    return round((value // HEATMAP_CELL_DEGREES) * HEATMAP_CELL_DEGREES, 6)


@router.get("/analytics")
async def get_dashboard_analytics(
    current_user: UserPublic = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    """Aggregations for the Dashboard screen: incident trend, per-day threat
    breakdown, an incident location heatmap, device health, and a weekly
    safety score.
    """
    today = datetime.now(timezone.utc).date()

    incidents = (
        (await session.execute(select(Incident).where(Incident.user_id == current_user.id)))
        .scalars()
        .all()
    )

    # --- Card 1: total + 30-day sparkline + trend vs the preceding 30 days --
    window_start = today - timedelta(days=TREND_WINDOW_DAYS - 1)
    prior_start = window_start - timedelta(days=TREND_WINDOW_DAYS)

    daily: dict[str, int] = {
        (window_start + timedelta(days=offset)).isoformat(): 0
        for offset in range(TREND_WINDOW_DAYS)
    }
    current_window = 0
    prior_window = 0
    for row in incidents:
        day = _date_of(row)
        if day is None:
            continue
        if day >= window_start:
            current_window += 1
            key = day.isoformat()
            if key in daily:
                daily[key] += 1
        elif day >= prior_start:
            prior_window += 1

    # Null, not zero: "no baseline to compare against" and "flat month on
    # month" are different facts, and the card renders them differently.
    trend_pct = (
        round((current_window - prior_window) / prior_window * 100, 1) if prior_window else None
    )

    # --- Card 2: threat level counts per day, last 14 days ------------------
    threat_window_start = today - timedelta(days=THREAT_BY_DAY_WINDOW_DAYS - 1)
    threat_by_day: dict[str, Counter] = {
        (threat_window_start + timedelta(days=offset)).isoformat(): Counter()
        for offset in range(THREAT_BY_DAY_WINDOW_DAYS)
    }
    for row in incidents:
        day = _date_of(row)
        if day is None or day < threat_window_start:
            continue
        key = day.isoformat()
        if key in threat_by_day:
            threat_by_day[key][(row.threat_level or "unknown").lower()] += 1

    # --- Card 3: heatmap over incident-linked locations ---------------------
    # Journey breadcrumbs share the locations table but describe routine
    # travel, so including them would turn an incident heatmap into a
    # commute map.
    incident_ids = {row.id for row in incidents}
    cells: Counter = Counter()
    if incident_ids:
        location_rows = (
            (
                await session.execute(
                    select(Location).where(
                        Location.user_id == current_user.id,
                        Location.incident_id.in_(incident_ids),
                    )
                )
            )
            .scalars()
            .all()
        )
        for loc in location_rows:
            cells[(_snap(loc.lat), _snap(loc.lng))] += 1

    # --- Card 4: threat level distribution ----------------------------------
    confidence_breakdown = Counter((row.threat_level or "unknown").lower() for row in incidents)

    # --- Card 5: three most recent incidents --------------------------------
    recent = sorted(
        (row for row in incidents if row.created_at is not None),
        key=lambda r: r.created_at,
        reverse=True,
    )[:3]

    # --- Card 6: device health ----------------------------------------------
    devices = (
        (await session.execute(select(Device).where(Device.user_id == current_user.id)))
        .scalars()
        .all()
    )

    # --- Card 7: weekly safety score ----------------------------------------
    score_window_start = today - timedelta(days=SAFETY_SCORE_WINDOW_DAYS - 1)
    penalty = 0
    incident_days: set[date] = set()
    for row in incidents:
        day = _date_of(row)
        if day is None:
            continue
        incident_days.add(day)
        if day >= score_window_start:
            penalty += _THREAT_WEIGHTS.get(
                (row.threat_level or "").lower(), _DEFAULT_THREAT_WEIGHT
            )

    # A brand-new account has no history to have been safe through, so the
    # streak is capped at the account's own age rather than running back to
    # the epoch and claiming twenty incident-free years.
    account_created = _date_of(current_user) or today
    streak = 0
    cursor = today
    while cursor not in incident_days and cursor >= account_created:
        streak += 1
        cursor -= timedelta(days=1)

    return {
        "total_incidents": len(incidents),
        "trend_pct": trend_pct,
        "incidents_last_30_days": [{"date": day, "count": count} for day, count in daily.items()],
        "threat_by_day": [
            {"date": day, "total": sum(counts.values()), "counts": dict(counts)}
            for day, counts in threat_by_day.items()
        ],
        "heatmap": {
            "cell_degrees": HEATMAP_CELL_DEGREES,
            "cells": [
                {"lat": lat, "lng": lng, "weight": weight}
                for (lat, lng), weight in sorted(cells.items(), key=lambda kv: -kv[1])
            ],
        },
        "confidence_breakdown": dict(confidence_breakdown),
        "recent_incidents": [
            {
                "id": row.id,
                "title": row.title,
                "threat_level": row.threat_level,
                "created_at": row.created_at,
            }
            for row in recent
        ],
        "device_health": [
            {
                "device_id": device.id,
                "device_name": device.device_name,
                "device_type": device.device_type,
                "battery_level": device.battery_level,
                "signal_strength": device.signal_strength,
                "is_active": device.is_active,
                "last_seen": device.last_seen,
            }
            for device in devices
        ],
        # No battery history is persisted anywhere, so there is no trend to
        # chart. Said out loud in the payload so the client renders current
        # readings instead of quietly drawing a straight line and calling it
        # a trend.
        "device_battery_history_available": False,
        "safety_score": {
            "score": max(0, 100 - penalty),
            "window_days": SAFETY_SCORE_WINDOW_DAYS,
            "incident_free_streak_days": streak,
        },
    }
