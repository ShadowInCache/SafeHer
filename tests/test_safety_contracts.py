"""In-process contract tests for the safety features: cancel PIN, trigger
preferences, and Safe Journeys.

The nearby-places endpoint is deliberately not covered here — it calls a live
third-party service (Overpass), so exercising it in a unit test would make the
suite depend on someone else's uptime and rate limit. Its parsing and distance
maths are pure functions and are covered separately below.
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
from fastapi_app.services import places


class TestSafetyContracts(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        )
        self.headers = {"Authorization": f"Bearer {await self._login()}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _login(self) -> str:
        email = f"safety-{uuid4().hex}@safeherapp.com"
        password = "TestPass123!"
        register = await self.client.post(
            "/api/v1/auth/register",
            json={"email": email, "password": password, "full_name": "Safety Test", "role": "user"},
        )
        self.assertEqual(register.status_code, 201, register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": password}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def _create_contact(self) -> str:
        response = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers=self.headers,
            json={"name": "Asha", "phone": "+911111111111", "relationship": "Sister", "priority": 1},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    # ------------------------------------------------------------------ auth

    async def test_safety_endpoints_require_authentication(self):
        for method, path in [
            ("get", "/api/v1/safety/pin"),
            ("get", "/api/v1/safety/preferences"),
            ("get", "/api/v1/journeys/active"),
            ("get", "/api/v1/journeys"),
        ]:
            response = await getattr(self.client, method)(path)
            self.assertEqual(response.status_code, 401, f"{method} {path} -> {response.text}")

    # ------------------------------------------------------------------- PIN

    async def test_pin_lifecycle_and_verification(self):
        status = await self.client.get("/api/v1/safety/pin", headers=self.headers)
        self.assertEqual(status.status_code, 200)
        self.assertFalse(status.json()["is_set"])

        created = await self.client.put(
            "/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"}
        )
        self.assertEqual(created.status_code, 200, created.text)
        self.assertTrue(created.json()["is_set"])

        good = await self.client.post(
            "/api/v1/safety/pin/verify", headers=self.headers, json={"pin": "4821"}
        )
        self.assertEqual(good.status_code, 200)
        self.assertTrue(good.json()["valid"])

        bad = await self.client.post(
            "/api/v1/safety/pin/verify", headers=self.headers, json={"pin": "0000"}
        )
        self.assertEqual(bad.status_code, 200)
        self.assertFalse(bad.json()["valid"])
        self.assertEqual(bad.json()["attempts_remaining"], 4)

    async def test_changing_a_pin_requires_the_current_one(self):
        await self.client.put("/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"})

        without_current = await self.client.put(
            "/api/v1/safety/pin", headers=self.headers, json={"pin": "1234"}
        )
        self.assertEqual(without_current.status_code, 400)

        wrong_current = await self.client.put(
            "/api/v1/safety/pin",
            headers=self.headers,
            json={"pin": "1234", "current_pin": "9999"},
        )
        self.assertEqual(wrong_current.status_code, 401)

        correct = await self.client.put(
            "/api/v1/safety/pin",
            headers=self.headers,
            json={"pin": "1234", "current_pin": "4821"},
        )
        self.assertEqual(correct.status_code, 200, correct.text)

        verify = await self.client.post(
            "/api/v1/safety/pin/verify", headers=self.headers, json={"pin": "1234"}
        )
        self.assertTrue(verify.json()["valid"])

    async def test_pin_is_never_returned_to_the_client(self):
        await self.client.put("/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"})
        status = await self.client.get("/api/v1/safety/pin", headers=self.headers)
        body = status.text
        self.assertNotIn("4821", body)
        self.assertNotIn("pin_hash", body)

    async def test_repeated_wrong_pins_lock_out(self):
        await self.client.put("/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"})

        for _ in range(5):
            response = await self.client.post(
                "/api/v1/safety/pin/verify", headers=self.headers, json={"pin": "0000"}
            )
            self.assertEqual(response.status_code, 200)

        locked = await self.client.post(
            "/api/v1/safety/pin/verify", headers=self.headers, json={"pin": "4821"}
        )
        self.assertFalse(locked.json()["valid"], "correct PIN should be refused while locked out")
        self.assertIsNotNone(locked.json()["locked_until"])

    # ----------------------------------------------------------- preferences

    async def test_preferences_default_to_every_trigger_off(self):
        response = await self.client.get("/api/v1/safety/preferences", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        body = response.json()
        # Anything that can raise an alarm must be opt-in.
        self.assertFalse(body["shake_trigger_enabled"])
        self.assertFalse(body["voice_commands_enabled"])
        self.assertFalse(body["require_pin_to_cancel"])

    async def test_requiring_a_pin_to_cancel_needs_a_pin_to_exist(self):
        rejected = await self.client.patch(
            "/api/v1/safety/preferences",
            headers=self.headers,
            json={"require_pin_to_cancel": True},
        )
        self.assertEqual(rejected.status_code, 400)

        await self.client.put("/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"})
        accepted = await self.client.patch(
            "/api/v1/safety/preferences",
            headers=self.headers,
            json={"require_pin_to_cancel": True},
        )
        self.assertEqual(accepted.status_code, 200, accepted.text)
        self.assertTrue(accepted.json()["require_pin_to_cancel"])

    async def test_removing_the_pin_clears_the_setting_that_depends_on_it(self):
        await self.client.put("/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"})
        await self.client.patch(
            "/api/v1/safety/preferences",
            headers=self.headers,
            json={"require_pin_to_cancel": True},
        )

        removed = await self.client.request(
            "DELETE", "/api/v1/safety/pin", headers=self.headers, json={"pin": "4821"}
        )
        self.assertEqual(removed.status_code, 204, removed.text)

        prefs = await self.client.get("/api/v1/safety/preferences", headers=self.headers)
        self.assertFalse(
            prefs.json()["require_pin_to_cancel"],
            "a cancel gate must not survive the PIN it depends on",
        )

    async def test_shake_sensitivity_is_range_checked(self):
        response = await self.client.patch(
            "/api/v1/safety/preferences", headers=self.headers, json={"shake_sensitivity": 9}
        )
        self.assertEqual(response.status_code, 422)

    # -------------------------------------------------------------- journeys

    async def test_journey_lifecycle(self):
        contact_id = await self._create_contact()

        none_yet = await self.client.get("/api/v1/journeys/active", headers=self.headers)
        self.assertEqual(none_yet.status_code, 200)
        self.assertIsNone(none_yet.json())

        started = await self.client.post(
            "/api/v1/journeys",
            headers=self.headers,
            json={
                "destination_label": "Home",
                "expected_duration_minutes": 30,
                "contact_ids": [contact_id],
            },
        )
        self.assertEqual(started.status_code, 201, started.text)
        journey = started.json()
        self.assertEqual(journey["status"], "active")
        self.assertEqual(journey["contact_ids"], [contact_id])

        duplicate = await self.client.post(
            "/api/v1/journeys",
            headers=self.headers,
            json={"destination_label": "Elsewhere", "expected_duration_minutes": 10},
        )
        self.assertEqual(duplicate.status_code, 409)

        breadcrumb = await self.client.post(
            f"/api/v1/journeys/{journey['id']}/locations",
            headers=self.headers,
            json={"latitude": 12.96, "longitude": 77.59, "accuracy_metres": 12.5},
        )
        self.assertEqual(breadcrumb.status_code, 204, breadcrumb.text)

        trail = await self.client.get(
            f"/api/v1/journeys/{journey['id']}/locations", headers=self.headers
        )
        self.assertEqual(len(trail.json()), 1)
        self.assertAlmostEqual(trail.json()[0]["latitude"], 12.96)

        arrived = await self.client.post(
            f"/api/v1/journeys/{journey['id']}/arrive", headers=self.headers
        )
        self.assertEqual(arrived.status_code, 200)
        self.assertEqual(arrived.json()["status"], "arrived")

        after = await self.client.get("/api/v1/journeys/active", headers=self.headers)
        self.assertIsNone(after.json())

    async def test_journey_cannot_escalate_before_its_deadline(self):
        started = await self.client.post(
            "/api/v1/journeys",
            headers=self.headers,
            json={"destination_label": "Home", "expected_duration_minutes": 60},
        )
        journey_id = started.json()["id"]

        early = await self.client.post(
            f"/api/v1/journeys/{journey_id}/escalate", headers=self.headers
        )
        self.assertEqual(early.status_code, 409, "the server must re-check the deadline itself")

    async def test_overdue_journey_escalates_and_records_an_incident(self):
        """The consequential path: deadline passes, an Incident is written, and
        the journey is marked overdue. Verified by backdating the deadline
        rather than sleeping through it."""
        from datetime import datetime, timedelta

        from fastapi_app.db import SessionLocal
        from fastapi_app.models import SafeJourney

        contact_id = await self._create_contact()
        started = await self.client.post(
            "/api/v1/journeys",
            headers=self.headers,
            json={
                "destination_label": "Home",
                "expected_duration_minutes": 30,
                "contact_ids": [contact_id],
            },
        )
        journey_id = started.json()["id"]

        incidents_before = await self.client.get("/api/v1/incidents/", headers=self.headers)
        count_before = len(incidents_before.json())

        async with SessionLocal() as session:
            journey = await session.get(SafeJourney, journey_id)
            journey.expected_arrival_at = datetime.utcnow() - timedelta(minutes=1)
            await session.commit()

        escalated = await self.client.post(
            f"/api/v1/journeys/{journey_id}/escalate", headers=self.headers
        )
        self.assertEqual(escalated.status_code, 200, escalated.text)
        self.assertEqual(escalated.json()["status"], "overdue")

        incidents_after = await self.client.get("/api/v1/incidents/", headers=self.headers)
        self.assertEqual(
            len(incidents_after.json()),
            count_before + 1,
            "an overdue journey must leave an auditable incident",
        )
        titles = [item["title"] for item in incidents_after.json()]
        self.assertIn("Safe Journey overdue", titles)

        # Escalating twice must not raise a second incident.
        again = await self.client.post(
            f"/api/v1/journeys/{journey_id}/escalate", headers=self.headers
        )
        self.assertEqual(again.status_code, 409)

    async def test_journey_rejects_contacts_from_another_account(self):
        # A contact id the caller doesn't own must not be attachable.
        other_client_token = await self._login()
        other_contact = await self.client.post(
            "/api/v1/users/me/emergency-contacts",
            headers={"Authorization": f"Bearer {other_client_token}"},
            json={"name": "Someone Else", "phone": "+912222222222", "priority": 1},
        )
        self.assertEqual(other_contact.status_code, 201)

        response = await self.client.post(
            "/api/v1/journeys",
            headers=self.headers,
            json={
                "destination_label": "Home",
                "expected_duration_minutes": 30,
                "contact_ids": [other_contact.json()["id"]],
            },
        )
        self.assertEqual(response.status_code, 400)

    async def test_journey_of_another_user_is_not_reachable(self):
        started = await self.client.post(
            "/api/v1/journeys",
            headers=self.headers,
            json={"destination_label": "Home", "expected_duration_minutes": 30},
        )
        journey_id = started.json()["id"]

        intruder = {"Authorization": f"Bearer {await self._login()}"}
        response = await self.client.get(
            f"/api/v1/journeys/{journey_id}/locations", headers=intruder
        )
        self.assertEqual(response.status_code, 404)


class TestPlacesHelpers(unittest.TestCase):
    """Pure helpers behind the nearby lookup — no network involved."""

    def test_distance_matches_a_known_separation(self):
        # Bengaluru MG Road -> Cubbon Park, ~1.2 km apart.
        metres = places._haversine_metres(12.9756, 77.6068, 12.9763, 77.5929)
        self.assertGreater(metres, 1000)
        self.assertLess(metres, 1700)

    def test_distance_is_zero_for_the_same_point(self):
        self.assertAlmostEqual(places._haversine_metres(12.9, 77.5, 12.9, 77.5), 0.0, places=3)

    def test_unnamed_elements_are_dropped(self):
        element = {"type": "node", "id": 1, "lat": 12.9, "lon": 77.5, "tags": {"amenity": "police"}}
        self.assertIsNone(places._element_to_place(element, 12.9, 77.5))

    def test_named_police_station_is_parsed_with_a_real_distance(self):
        element = {
            "type": "node",
            "id": 1,
            "lat": 12.9800,
            "lon": 77.6068,
            "tags": {"amenity": "police", "name": "Ashok Nagar Police Station", "phone": "+918022001100"},
        }
        place = places._element_to_place(element, 12.9756, 77.6068)
        self.assertIsNotNone(place)
        self.assertEqual(place["category"], "police")
        self.assertEqual(place["name"], "Ashok Nagar Police Station")
        self.assertEqual(place["phone"], "+918022001100")
        self.assertGreater(place["distance_metres"], 0)

    def test_way_elements_use_their_centre_point(self):
        element = {
            "type": "way",
            "id": 2,
            "center": {"lat": 12.98, "lon": 77.61},
            "tags": {"amenity": "hospital", "name": "General Hospital"},
        }
        place = places._element_to_place(element, 12.9756, 77.6068)
        self.assertIsNotNone(place)
        self.assertEqual(place["category"], "hospital")

    def test_untagged_categories_are_ignored(self):
        element = {
            "type": "node",
            "id": 3,
            "lat": 12.9,
            "lon": 77.5,
            "tags": {"amenity": "nightclub", "name": "Somewhere"},
        }
        self.assertIsNone(places._element_to_place(element, 12.9, 77.5))

    def test_every_supported_category_has_filters(self):
        for category in places.SUPPORTED_CATEGORIES:
            self.assertIn(category, places._CATEGORY_FILTERS)
            self.assertTrue(places._CATEGORY_FILTERS[category])


if __name__ == "__main__":
    unittest.main()
