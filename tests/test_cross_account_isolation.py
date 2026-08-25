"""Cross-account (tenant) isolation tests.

Every other API test in this suite drives a single account, which is exactly
the shape of test that cannot catch an isolation failure: a query missing its
`user_id` filter returns the right rows when only one user exists. These tests
run two accounts against one server and assert that neither can see, edit or
delete the other's data.

The trigger was a report of one account's emergency contact appearing under
another account. That turned out to be client-side state, not the API -- but
"the API was fine this time" is only worth anything if something keeps
checking, and the contact repository *was* looking rows up by id alone with
the ownership check left to each caller.
"""

import unittest
from uuid import uuid4

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app


class TestCrossAccountIsolation(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.a_email = f"iso-a-{uuid4().hex}@safeherapp.com"
        self.b_email = f"iso-b-{uuid4().hex}@safeherapp.com"
        self.a = {"Authorization": f"Bearer {await self._login(self.a_email)}"}
        self.b = {"Authorization": f"Bearer {await self._login(self.b_email)}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self, email: str) -> str:
        register = await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Isolation Test",
                "phone": "+15550100000",
            },
        )
        self.assertIn(register.status_code, (201, 200), register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def _add_contact(self, headers, name: str) -> dict:
        response = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            json={
                "name": name,
                "phone": "+15550101001",
                "relationship": "Sister",
                "email": "contact@example.com",
            },
            headers=headers,
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    # ---------------------------------------------------------------- contacts

    async def test_b_cannot_list_a_contacts(self):
        await self._add_contact(self.a, "Account A Contact")

        response = await self.client.get(
            "/api/v1/users/me/emergency-contacts", headers=self.b
        )

        self.assertEqual(response.status_code, 200, response.text)
        names = [c["name"] for c in response.json()]
        self.assertNotIn("Account A Contact", names)
        self.assertEqual(names, [], "a fresh account starts with no contacts")

    async def test_b_cannot_read_a_contact_by_id(self):
        contact = await self._add_contact(self.a, "Account A Contact")

        # There is no single-contact GET, so the edit route is the read path
        # an attacker would reach for: it 404s before touching anything.
        response = await self.client.put(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}",
            json={"name": "probe"},
            headers=self.b,
        )

        self.assertEqual(response.status_code, 404, response.text)

    async def test_b_cannot_edit_a_contact(self):
        contact = await self._add_contact(self.a, "Account A Contact")

        response = await self.client.put(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}",
            json={"name": "Hijacked", "phone": "+19999999999"},
            headers=self.b,
        )
        self.assertEqual(response.status_code, 404, response.text)

        # And A's copy is untouched.
        listing = await self.client.get(
            "/api/v1/users/me/emergency-contacts", headers=self.a
        )
        names = [c["name"] for c in listing.json()]
        self.assertIn("Account A Contact", names)
        self.assertNotIn("Hijacked", names)

    async def test_b_cannot_delete_a_contact(self):
        contact = await self._add_contact(self.a, "Account A Contact")

        response = await self.client.delete(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}", headers=self.b
        )

        # Survival is asserted before the status code on purpose. The status
        # is the API being polite; the row still existing is the security
        # property, and if only one of the two can hold it should be this one.
        listing = await self.client.get(
            "/api/v1/users/me/emergency-contacts", headers=self.a
        )
        self.assertEqual(
            [c["id"] for c in listing.json()],
            [contact["id"]],
            "A's contact must survive B's delete attempt",
        )
        self.assertEqual(response.status_code, 404, response.text)

    async def test_b_cannot_trigger_verification_on_a_contact(self):
        contact = await self._add_contact(self.a, "Account A Contact")

        response = await self.client.post(
            f"/api/v1/users/me/emergency-contacts/{contact['id']}/verify/send",
            headers=self.b,
        )

        self.assertEqual(response.status_code, 404, response.text)

    async def test_each_account_sees_only_its_own_contacts(self):
        await self._add_contact(self.a, "A Only")
        await self._add_contact(self.b, "B Only")

        a_names = [
            c["name"]
            for c in (
                await self.client.get(
                    "/api/v1/users/me/emergency-contacts", headers=self.a
                )
            ).json()
        ]
        b_names = [
            c["name"]
            for c in (
                await self.client.get(
                    "/api/v1/users/me/emergency-contacts", headers=self.b
                )
            ).json()
        ]

        self.assertEqual(a_names, ["A Only"])
        self.assertEqual(b_names, ["B Only"])

    # ---------------------------------------------------------------- profile

    async def test_me_returns_the_caller_not_the_last_caller(self):
        a_me = await self.client.get("/api/v1/users/me", headers=self.a)
        b_me = await self.client.get("/api/v1/users/me", headers=self.b)

        self.assertEqual(a_me.status_code, 200, a_me.text)
        self.assertEqual(b_me.status_code, 200, b_me.text)
        self.assertEqual(a_me.json()["email"], self.a_email)
        self.assertEqual(b_me.json()["email"], self.b_email)
        self.assertNotEqual(a_me.json()["id"], b_me.json()["id"])

    async def test_profile_edits_do_not_cross_accounts(self):
        patched = await self.client.patch(
            "/api/v1/users/me", json={"full_name": "A Renamed"}, headers=self.a
        )
        self.assertIn(patched.status_code, (200, 204), patched.text)

        b_me = await self.client.get("/api/v1/users/me", headers=self.b)
        self.assertNotEqual(b_me.json().get("full_name"), "A Renamed")

    # ------------------------------------------------------------------ auth

    async def test_no_token_is_rejected(self):
        response = await self.client.get("/api/v1/users/me/emergency-contacts")
        self.assertIn(response.status_code, (401, 403), response.text)

    async def test_garbage_token_is_rejected(self):
        response = await self.client.get(
            "/api/v1/users/me/emergency-contacts",
            headers={"Authorization": "Bearer not-a-real-token"},
        )
        self.assertIn(response.status_code, (401, 403), response.text)


if __name__ == "__main__":
    unittest.main()
