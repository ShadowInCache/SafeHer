from typing import Any

import httpx
from fastapi import HTTPException, status

from fastapi_app.config import Settings


async def process_threat(settings: Settings, payload: dict[str, Any]) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(f"{settings.event_processor_url}/process_threat", json=payload)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Event processor unavailable: {exc}",
        ) from exc

    if response.status_code >= 400:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Event processor error: {response.text}",
        )

    data = response.json()
    if isinstance(data, dict):
        return data
    return {"data": data}


async def fetch_processor_status(settings: Settings) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(f"{settings.event_processor_url}/status")
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, dict) else {"data": data}
    except httpx.HTTPError as exc:
        return {"status": "unavailable", "detail": str(exc)}
