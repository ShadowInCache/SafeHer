import asyncio
import json
import logging
import ssl
from contextlib import AsyncExitStack
from datetime import datetime
import time
from typing import Optional

from asyncio_mqtt import Client, MqttError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from fastapi_app import models
from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal
from fastapi_app.realtime import manager

logger = logging.getLogger(__name__)

TOPIC_PATTERNS = [
    "safeher/devices/+/events",
    "safeher/devices/+/heartbeat",
    "safeher/devices/+/emergency",
    # Backward compatibility with older payload contracts
    "devices/+/events",
    # Legacy firmware topics
    "safeher/+/motion/data",
    "safeher/+/vision/frame",
    "safeher/+/heartbeat/status",
    "safeher/+/emergency/alert",
    "safeher/+/emergency/cancelled",
]

_mqtt_connected = False
_mqtt_last_message_ts: Optional[float] = None
_mqtt_message_count: int = 0
_mqtt_last_latency_ms: Optional[float] = None
_mqtt_avg_latency_ms: Optional[float] = None


def _parse_topic(topic: str) -> tuple[Optional[str], str]:
    parts = topic.split("/")
    if len(parts) == 4 and parts[0] == "safeher" and parts[1] == "devices":
        return parts[2], parts[3]
    if len(parts) == 3 and parts[0] == "devices":
        return parts[1], parts[2]

    # Legacy shape: safeher/<device_id>/<namespace>/<action>
    if len(parts) == 4 and parts[0] == "safeher":
        device_id = parts[1]
        namespace = parts[2]
        action = parts[3]
        if namespace == "motion" and action == "data":
            return device_id, "events"
        if namespace == "vision" and action == "frame":
            return device_id, "events"
        if namespace == "heartbeat" and action == "status":
            return device_id, "heartbeat"
        if namespace == "emergency" and action == "alert":
            return device_id, "emergency"
        if namespace == "emergency" and action == "cancelled":
            return device_id, "cancelled"

    return None, "unknown"


async def _handle_event_message(session: AsyncSession, topic: str, payload: str) -> None:
    start_ts = time.monotonic()

    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        logger.warning("Dropping MQTT message with invalid JSON on %s", topic)
        return

    device_id, event_type = _parse_topic(topic)
    if not device_id:
        logger.warning("Unexpected topic format: %s", topic)
        return

    device = await session.get(models.Device, device_id)
    if not device:
        # Compatibility lookup for firmware IDs that map to device_name.
        rows = await session.execute(
            select(models.Device).where(models.Device.device_name == device_id).limit(1)
        )
        device = rows.scalars().first()

    if not device and data.get("device_id"):
        fallback_id = str(data.get("device_id"))
        rows = await session.execute(
            select(models.Device).where(models.Device.device_name == fallback_id).limit(1)
        )
        device = rows.scalars().first()

    if not device:
        logger.warning("Unknown device on topic %s", topic)
        return
    if not device.is_active:
        logger.warning("Inactive device on topic %s", topic)
        return

    settings = get_settings()

    # Require auth_secret for device-originated events in production-like environments.
    auth_secret = data.get("auth_secret")
    if not auth_secret or auth_secret != device.auth_secret:
        if settings.environment in {"production", "staging"}:
            logger.warning("Unauthorized MQTT message for device %s", device.id)
            return
        logger.warning(
            "Device %s published without valid auth_secret; accepted in %s only",
            device.id,
            settings.environment,
        )

    device.last_seen = datetime.utcnow()

    # Persist only actionable event types as incidents.
    incident: Optional[models.Incident] = None
    if event_type in {"events", "emergency"}:
        threat_level = data.get("threat_level")
        if not threat_level:
            if event_type == "emergency":
                threat_level = "critical"
            elif data.get("motion_data", {}).get("threat_detected_local"):
                threat_level = "high"
            else:
                threat_level = "medium"

        title = data.get("title")
        if not title:
            data_type = str(data.get("data_type", "event")).title()
            title = f"Device {data_type}"

        incident = models.Incident(
            user_id=device.user_id,
            title=title,
            description=data.get("description") or json.dumps(data)[:1000],
            threat_level=threat_level,
            evidence_url=data.get("evidence_url"),
        )
        session.add(incident)

    await session.commit()

    outbound = {
        "type": "device_event",
        "topic": topic,
        "event_type": event_type,
        "device_id": device.id,
        "user_id": device.user_id,
        "payload": data,
        "timestamp": datetime.utcnow().isoformat(),
    }
    if incident is not None:
        await session.refresh(incident)
        outbound["incident_id"] = incident.id
        outbound["threat_level"] = incident.threat_level

    await manager.broadcast_to_user(device.user_id, outbound)

    end_ts = time.monotonic()
    _record_message_metrics(start_ts, end_ts)


async def mqtt_worker(stop_event: Optional[asyncio.Event] = None) -> None:
    settings = get_settings()
    tls_context = None
    if settings.mqtt_tls_enabled:
        tls_context = (
            ssl.create_default_context(cafile=settings.mqtt_tls_ca_path)
            if settings.mqtt_tls_ca_path
            else ssl.create_default_context()
        )

    client = Client(
        hostname=settings.mqtt_host,
        port=settings.mqtt_port,
        username=settings.mqtt_username,
        password=settings.mqtt_password,
        tls_context=tls_context,
    )

    while True:
        try:
            async with AsyncExitStack() as stack:
                await stack.enter_async_context(client)
                subscriptions = []
                for topic in TOPIC_PATTERNS:
                    subscriptions.append(
                        await stack.enter_async_context(client.filtered_messages(topic))
                    )
                    await client.subscribe(topic, qos=1)

                global _mqtt_connected
                _mqtt_connected = True
                logger.info("Subscribed to MQTT topics: %s", ", ".join(TOPIC_PATTERNS))

                while True:
                    for stream in subscriptions:
                        try:
                            message = await asyncio.wait_for(stream.__anext__(), timeout=0.2)
                        except TimeoutError:
                            continue
                        except StopAsyncIteration:
                            continue

                        async with SessionLocal() as session:
                            await _handle_event_message(
                                session,
                                str(message.topic),
                                message.payload.decode(),
                            )

                    if stop_event and stop_event.is_set():
                        _mark_disconnected()
                        return

        except MqttError as exc:
            logger.error("MQTT error: %s", exc)
            _mark_disconnected()
            await asyncio.sleep(3)

        if stop_event and stop_event.is_set():
            _mark_disconnected()
            break


def is_mqtt_connected() -> bool:
    return _mqtt_connected


def get_mqtt_status() -> dict:
    settings = get_settings()
    age = _mqtt_age_seconds()
    return {
        "connected": _mqtt_connected,
        "last_message_s": age,
        "stale": True if age is None else age > settings.mqtt_stale_after_seconds,
        "stale_threshold_s": settings.mqtt_stale_after_seconds,
        "message_count": _mqtt_message_count,
        "last_latency_ms": _mqtt_last_latency_ms,
        "avg_latency_ms": _mqtt_avg_latency_ms,
        "topics": TOPIC_PATTERNS,
    }


def _mqtt_age_seconds() -> Optional[float]:
    if _mqtt_last_message_ts is None:
        return None
    return max(0.0, time.monotonic() - _mqtt_last_message_ts)


def _record_message_metrics(start_ts: float, end_ts: float) -> None:
    global _mqtt_last_message_ts, _mqtt_message_count, _mqtt_last_latency_ms, _mqtt_avg_latency_ms
    _mqtt_message_count += 1
    _mqtt_last_message_ts = end_ts
    latency_ms = max(0.0, (end_ts - start_ts) * 1000.0)
    _mqtt_last_latency_ms = latency_ms
    alpha = 0.2
    if _mqtt_avg_latency_ms is None:
        _mqtt_avg_latency_ms = latency_ms
    else:
        _mqtt_avg_latency_ms = (_mqtt_avg_latency_ms * (1 - alpha)) + (latency_ms * alpha)


def _mark_disconnected() -> None:
    global _mqtt_connected, _mqtt_last_message_ts
    _mqtt_connected = False
    _mqtt_last_message_ts = None
