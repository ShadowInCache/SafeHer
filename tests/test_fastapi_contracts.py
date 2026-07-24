"""In-process FastAPI contract tests for versioned SafeHer endpoints."""

from __future__ import annotations

import os
import unittest
from unittest.mock import patch
from uuid import uuid4

# Configure test-safe settings before FastAPI app import.
os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "WARNING"

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.services.firebase_auth import FirebaseIdentity


class TestFastAPIContracts(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _register_and_login(self) -> tuple[str, str]:
        email = f"test-{uuid4().hex}@safeherapp.com"
        password = "TestPass123!"

        register_response = await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": password,
                "full_name": "Contract Test User",
                "role": "user",
            },
        )
        self.assertEqual(register_response.status_code, 201, register_response.text)

        login_response = await self.client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": password},
        )
        self.assertEqual(login_response.status_code, 200, login_response.text)

        token = login_response.json().get("access_token")
        self.assertIsInstance(token, str)
        self.assertTrue(token)

        return email, token

    async def test_health_and_openapi_endpoints(self):
        health = await self.client.get("/api/v1/health")
        self.assertEqual(health.status_code, 200, health.text)
        self.assertIn("status", health.json())

        openapi = await self.client.get("/api/v1/openapi.json")
        self.assertEqual(openapi.status_code, 200, openapi.text)
        self.assertIn("paths", openapi.json())

    async def test_auth_contract_register_login_me(self):
        email, token = await self._register_and_login()

        me = await self.client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(me.status_code, 200, me.text)
        self.assertEqual(me.json().get("email"), email)

    async def test_users_contacts_crud_contract(self):
        _, token = await self._register_and_login()
        headers = {"Authorization": f"Bearer {token}"}

        contact_id = str(uuid4())
        create = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=headers,
            json={
                "id": contact_id,
                "name": "Guardian One",
                "phone": "+15550000001",
                "relationship": "guardian",
                "priority": 1,
            },
        )
        self.assertEqual(create.status_code, 201, create.text)

        listing = await self.client.get(
            "/api/v1/users/me/emergency-contacts",
            headers=headers,
        )
        self.assertEqual(listing.status_code, 200, listing.text)
        ids = [item.get("id") for item in listing.json()]
        self.assertIn(contact_id, ids)

        delete = await self.client.delete(
            f"/api/v1/users/me/emergency-contacts/{contact_id}",
            headers=headers,
        )
        self.assertEqual(delete.status_code, 204, delete.text)

    async def test_firebase_exchange_endpoint_contract(self):
        response = await self.client.post(
            "/api/v1/auth/firebase/exchange",
            json={
                "id_token": "invalid.firebase.token",
                "role": "user",
            },
        )
        self.assertIn(response.status_code, {401, 503}, response.text)

    @patch("fastapi_app.routers.auth.verify_firebase_id_token")
    async def test_firebase_exchange_success_flow(self, mocked_verify):
        email = f"firebase-{uuid4().hex}@safeherapp.com"
        mocked_verify.return_value = FirebaseIdentity(
            uid="firebase-uid-123",
            email=email,
            name="Firebase User",
            raw_claims={"uid": "firebase-uid-123", "email": email},
        )

        exchange = await self.client.post(
            "/api/v1/auth/firebase/exchange",
            json={
                "id_token": "header.payload.signature",
                "role": "admin",
                "full_name": "Firebase User",
            },
        )
        self.assertEqual(exchange.status_code, 200, exchange.text)

        token = exchange.json().get("access_token")
        self.assertTrue(token)

        me = await self.client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(me.status_code, 200, me.text)
        self.assertEqual(me.json().get("email"), email)
        self.assertEqual(me.json().get("role"), "user")


if __name__ == "__main__":
    unittest.main()
