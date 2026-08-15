"""In-process contract tests for `GET /api/v1/dashboard/analytics`, which
backs SRS Part 3, SCREEN 9.

The point of these tests is less "does it return 200" than "does it refuse to
invent numbers". A safety dashboard that fabricates a downward trend, or draws
a battery line from a single reading, is worse than one that shows nothing --
so the assertions below pin the honesty properties (null trend without a
baseline, empty heatmap without incident locations, an explicit
`device_battery_history_available: false`) as hard contract.
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
from fastapi_app.routers.dashboard import (
    HEATMAP_CELL_DEGREES,
    SAFETY_SCORE_WINDOW_DAYS,
    THREAT_BY_DAY_WINDOW_DAYS,
    TREND_WINDOW_DAYS,
    _snap,
)


class TestDashboardAnalytics(unittest.IsolatedAsyncioTestCase):
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
        email = f"dash-{uuid4().hex}@safeherapp.com"
        password = "TestPass123!"
        register = await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": password,
                "full_name": "Dashboard Test",
                "role": "user",
            },
        )
        self.assertEqual(register.status_code, 201, register.text)
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": password}
        )
        self.assertEqual(login.status_code, 200, login.text)
        return login.json()["access_token"]

    async def _analytics(self) -> dict:
        response = await self.client.get("/api/v1/dashboard/analytics", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    async def _create_incident(self, *, threat_level: str, title: str = "Incident") -> str:
        response = await self.client.post(
            "/api/v1/incidents/",
            headers=self.headers,
            json={"title": title, "threat_level": threat_level},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    async def _trigger_emergency(self, *, lat: float, lng: float, severity: str = "high") -> str:
        response = await self.client.post(
            "/api/v1/alerts/emergency",
            headers=self.headers,
            json={
                "severity": severity,
                "summary": "SOS",
                "location": {"latitude": lat, "longitude": lng, "accuracy": 5.0},
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["id"]

    # ------------------------------------------------------------------ auth

    async def test_requires_authentication(self):
        response = await self.client.get("/api/v1/dashboard/analytics")
        self.assertIn(response.status_code, (401, 403), response.text)

    # ---------------------------------------------------------- empty account

    async def test_new_account_reports_nothing_rather_than_zeroes(self):
        data = await self._analytics()

        self.assertEqual(data["total_incidents"], 0)
        # No prior window to compare against: null, not "0% change", which
        # would read as a real measurement.
        self.assertIsNone(data["trend_pct"])
        self.assertEqual(data["confidence_breakdown"], {})
        self.assertEqual(data["recent_incidents"], [])
        self.assertEqual(data["heatmap"]["cells"], [])
        self.assertEqual(data["device_health"], [])

    async def test_windows_are_fully_populated_and_chronological(self):
        data = await self._analytics()

        sparkline = data["incidents_last_30_days"]
        self.assertEqual(len(sparkline), TREND_WINDOW_DAYS)
        self.assertEqual(sparkline, sorted(sparkline, key=lambda point: point["date"]))
        self.assertTrue(all(point["count"] == 0 for point in sparkline))

        by_day = data["threat_by_day"]
        self.assertEqual(len(by_day), THREAT_BY_DAY_WINDOW_DAYS)
        self.assertEqual(by_day, sorted(by_day, key=lambda point: point["date"]))
        self.assertTrue(all(point["counts"] == {} for point in by_day))

    async def test_perfect_score_when_no_incidents(self):
        score = (await self._analytics())["safety_score"]

        self.assertEqual(score["score"], 100)
        self.assertEqual(score["window_days"], SAFETY_SCORE_WINDOW_DAYS)
        # The account was created today, so it cannot claim more than one
        # incident-free day of history.
        self.assertEqual(score["incident_free_streak_days"], 1)

    # -------------------------------------------------------------- incidents

    async def test_incidents_land_in_todays_bucket(self):
        await self._create_incident(threat_level="low")
        await self._create_incident(threat_level="high")

        data = await self._analytics()

        self.assertEqual(data["total_incidents"], 2)
        self.assertEqual(data["confidence_breakdown"], {"low": 1, "high": 1})
        self.assertEqual(sum(point["count"] for point in data["incidents_last_30_days"]), 2)

        today = data["threat_by_day"][-1]
        self.assertEqual(today["total"], 2)
        self.assertEqual(today["counts"], {"low": 1, "high": 1})

    async def test_recent_incidents_are_newest_first_and_capped_at_three(self):
        for index in range(4):
            await self._create_incident(threat_level="medium", title=f"Incident {index}")

        recent = (await self._analytics())["recent_incidents"]

        self.assertEqual(len(recent), 3)
        timestamps = [row["created_at"] for row in recent]
        self.assertEqual(timestamps, sorted(timestamps, reverse=True))

    async def test_unlabelled_incidents_are_bucketed_not_dropped(self):
        await self._create_incident(threat_level=None)

        data = await self._analytics()

        self.assertEqual(data["confidence_breakdown"], {"unknown": 1})
        # And they cost the same as a medium, so an absent label can never
        # make the week look safer than it was.
        self.assertEqual(data["safety_score"]["score"], 90)

    async def test_score_penalises_by_severity_and_breaks_the_streak(self):
        await self._create_incident(threat_level="critical")

        score = (await self._analytics())["safety_score"]

        self.assertEqual(score["score"], 70)
        self.assertEqual(score["incident_free_streak_days"], 0)

    async def test_score_floors_at_zero(self):
        for _ in range(5):
            await self._create_incident(threat_level="critical")

        self.assertEqual((await self._analytics())["safety_score"]["score"], 0)

    # ---------------------------------------------------------------- heatmap

    async def test_heatmap_aggregates_incident_locations_into_cells(self):
        # Two SOS triggers a few metres apart must collapse into one cell;
        # a third, ~2 km away, must not.
        await self._trigger_emergency(lat=17.3850, lng=78.4867)
        await self._trigger_emergency(lat=17.3851, lng=78.4868)
        await self._trigger_emergency(lat=17.4050, lng=78.4867)

        heatmap = (await self._analytics())["heatmap"]

        self.assertEqual(heatmap["cell_degrees"], HEATMAP_CELL_DEGREES)
        self.assertEqual(len(heatmap["cells"]), 2)
        # Heaviest cell first, so the client can render without re-sorting.
        self.assertEqual([cell["weight"] for cell in heatmap["cells"]], [2, 1])
        self.assertEqual(heatmap["cells"][0]["lat"], _snap(17.3850))

    async def test_incidents_without_a_location_stay_out_of_the_heatmap(self):
        await self._create_incident(threat_level="high")

        data = await self._analytics()

        self.assertEqual(data["total_incidents"], 1)
        self.assertEqual(data["heatmap"]["cells"], [])

    # ---------------------------------------------------------- device health

    async def test_device_health_reports_current_readings_only(self):
        register = await self.client.post(
            "/api/v1/devices/register",
            headers=self.headers,
            json={"device_name": "Glove", "device_type": "glove"},
        )
        self.assertEqual(register.status_code, 200, register.text)

        data = await self._analytics()

        self.assertEqual(len(data["device_health"]), 1)
        self.assertEqual(data["device_health"][0]["device_name"], "Glove")
        # The schema stores one current battery reading per device, so the
        # payload states outright that there is no series to chart.
        self.assertFalse(data["device_battery_history_available"])

    # ---------------------------------------------------------------- scoping

    async def test_another_users_incidents_are_invisible(self):
        await self._create_incident(threat_level="critical")

        other = {"Authorization": f"Bearer {await self._login()}"}
        response = await self.client.get("/api/v1/dashboard/analytics", headers=other)
        self.assertEqual(response.status_code, 200, response.text)

        data = response.json()
        self.assertEqual(data["total_incidents"], 0)
        self.assertEqual(data["safety_score"]["score"], 100)


if __name__ == "__main__":
    unittest.main()
