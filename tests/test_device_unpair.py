"""Removing a paired wearable — a route that did not exist.

A device paired once stayed on the account permanently. The app could drop
the Bluetooth link locally, and the server would still list the wearable as
registered. A woman who has given a glove away, or had one taken from her,
had no way to say so — and its push tokens kept receiving her emergency
notifications.
"""

from __future__ import annotations

import os
import unittest
from uuid import uuid4

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app


class TestUnpair(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.headers = {"Authorization": f"Bearer {await self._login()}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self) -> str:
        email = f"unpair-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": "TestPass123!", "full_name": "U", "role": "user"},
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        return login.json()["access_token"]

    async def _register_device(self, headers=None) -> str:
        response = await self.client.post(
            "/api/v1/devices/register",
            headers=headers or self.headers,
            json={"device_name": f"glove-{uuid4().hex[:6]}", "device_type": "glove"},
        )
        return response.json()["id"]

    async def test_a_paired_device_can_be_removed(self):
        device_id = await self._register_device()

        response = await self.client.delete(
            f"/api/v1/devices/{device_id}", headers=self.headers
        )

        self.assertEqual(response.status_code, 204, response.text)

    async def test_it_disappears_from_the_list(self):
        device_id = await self._register_device()
        await self.client.delete(f"/api/v1/devices/{device_id}", headers=self.headers)

        listed = await self.client.get("/api/v1/devices/me", headers=self.headers)

        self.assertNotIn(device_id, [d["id"] for d in listed.json()])

    async def test_other_devices_are_untouched(self):
        keep = await self._register_device()
        remove = await self._register_device()

        await self.client.delete(f"/api/v1/devices/{remove}", headers=self.headers)

        listed = await self.client.get("/api/v1/devices/me", headers=self.headers)
        self.assertIn(keep, [d["id"] for d in listed.json()])

    async def test_another_user_cannot_unpair_your_device(self):
        # The obvious abuse: unpairing someone else's glove would silently
        # remove their wearable protection.
        device_id = await self._register_device()
        other = {"Authorization": f"Bearer {await self._login()}"}

        response = await self.client.delete(f"/api/v1/devices/{device_id}", headers=other)

        self.assertEqual(response.status_code, 404, response.text)

    async def test_a_missing_device_looks_the_same_as_someone_elses(self):
        # Same 404 either way. Distinguishing them lets any signed-in user
        # probe for valid device ids.
        response = await self.client.delete(
            f"/api/v1/devices/{uuid4()}", headers=self.headers
        )

        self.assertEqual(response.status_code, 404)

    async def test_unpairing_requires_authentication(self):
        device_id = await self._register_device()

        response = await self.client.delete(f"/api/v1/devices/{device_id}")

        self.assertIn(response.status_code, (401, 403))


if __name__ == "__main__":
    unittest.main()
