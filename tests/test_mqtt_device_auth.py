"""Device-originated MQTT events must prove who they are.

An event on `safeher/<device_id>/emergency` creates an `Incident` owned by
whoever owns that device, and an incident notifies that person's emergency
contacts. So the identity in the topic is a claim about *someone else's* alarm,
and it has to be proved rather than believed.

The way it failed before: the `auth_secret` check ran only when
`settings.environment` was exactly `"production"` or `"staging"` -- a
case-sensitive comparison against a field whose default is `"development"`. An
unset ENVIRONMENT, or `"prod"`, or `"Production"`, accepted unauthenticated
events and created incidents from them. Authentication is now unconditional
unless an operator deliberately opts out.
"""

import asyncio
import json
import unittest
import uuid

from sqlalchemy import select

from fastapi_app.config import get_settings
from fastapi_app.db import SessionLocal, init_db
from fastapi_app import models
from fastapi_app.mqtt_service import _handle_event_message


def _run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


class MqttDeviceAuthTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.settings = get_settings()
        self._original_opt_out = self.settings.allow_unauthenticated_device_events
        self.settings.allow_unauthenticated_device_events = False

        self.secret = uuid.uuid4().hex
        self.device_id = f"dev-{uuid.uuid4().hex[:10]}"
        self.user_id = f"user-{uuid.uuid4().hex[:10]}"

        async with SessionLocal() as session:
            session.add(models.User(
                id=self.user_id,
                email=f"mqtt-{uuid.uuid4().hex[:8]}@safeherapp.com",
                password_hash="x",
                full_name="MQTT Owner",
            ))
            session.add(models.Device(
                id=self.device_id,
                user_id=self.user_id,
                device_name=self.device_id,
                device_type="glove",
                auth_secret=self.secret,
                is_active=True,
            ))
            await session.commit()

    async def asyncTearDown(self):
        self.settings.allow_unauthenticated_device_events = self._original_opt_out

    async def _incident_count(self) -> int:
        async with SessionLocal() as session:
            rows = await session.execute(
                select(models.Incident).where(models.Incident.user_id == self.user_id)
            )
            return len(rows.scalars().all())

    async def _publish(self, payload: dict, device_id=None):
        topic = f"safeher/devices/{device_id or self.device_id}/emergency"
        async with SessionLocal() as session:
            await _handle_event_message(session, topic, json.dumps(payload))

    # ------------------------------------------------------------------ pass

    async def test_a_device_with_its_own_secret_is_accepted(self):
        # The capability has to still work, or the test above it proves nothing.
        before = await self._incident_count()

        await self._publish({"auth_secret": self.secret, "title": "Real alarm"})

        self.assertEqual(await self._incident_count(), before + 1)

    # ------------------------------------------------------------------ fail

    async def test_an_event_with_no_secret_raises_no_incident(self):
        before = await self._incident_count()

        await self._publish({"title": "Forged alarm"})

        self.assertEqual(
            await self._incident_count(), before,
            "an unauthenticated publish created an incident in a user's account",
        )

    async def test_an_event_with_the_wrong_secret_raises_no_incident(self):
        before = await self._incident_count()

        await self._publish({"auth_secret": "not-the-secret", "title": "Forged"})

        self.assertEqual(await self._incident_count(), before)

    async def test_rejection_does_not_depend_on_the_environment_string(self):
        # The original bug in one assertion: with ENVIRONMENT at its
        # "development" default -- which is what an unset variable gives you --
        # an unauthenticated event used to be accepted.
        self.settings.environment = "development"
        before = await self._incident_count()

        await self._publish({"title": "Forged under a dev-looking env"})

        self.assertEqual(await self._incident_count(), before)

    async def test_the_payload_cannot_name_a_different_device(self):
        # Identity comes from the topic, never the body. The body naming a
        # device was a second way to choose whose account an event landed in.
        before = await self._incident_count()

        await self._publish(
            {"auth_secret": self.secret, "device_id": self.device_id, "title": "x"},
            device_id="a-device-that-does-not-exist",
        )

        self.assertEqual(await self._incident_count(), before)

    async def test_an_inactive_device_cannot_publish(self):
        async with SessionLocal() as session:
            device = await session.get(models.Device, self.device_id)
            device.is_active = False
            await session.commit()

        before = await self._incident_count()
        await self._publish({"auth_secret": self.secret, "title": "After revocation"})

        self.assertEqual(
            await self._incident_count(), before,
            "a revoked device could still raise alarms in its old owner's account",
        )

    # ----------------------------------------------------------- the defaults

    async def test_the_insecure_opt_out_is_off_by_default(self):
        # A deployment that forgets a variable must not lose authentication.
        fresh = get_settings()
        self.assertFalse(
            type(fresh).model_fields["allow_unauthenticated_device_events"].default
        )

    async def test_the_mqtt_worker_is_off_by_default(self):
        # No current firmware publishes MQTT: the glove is BLE and the glasses
        # are HTTP. An ingest path nothing feeds is attack surface with no
        # corresponding feature.
        fresh = get_settings()
        self.assertFalse(type(fresh).model_fields["enable_mqtt_worker"].default)


if __name__ == "__main__":
    unittest.main()
