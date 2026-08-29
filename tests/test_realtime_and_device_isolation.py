"""The two authorization boundaries the IDOR sweep never reached.

`test_idor_all_resources.py` and `test_cross_account_isolation.py` between them
cover incidents, evidence, journeys, shares, contacts, devices and summaries.
Two ID-bearing routes were outside both, and this file closes them:

* **`WS /api/v1/ws/alerts/{user_id}`** had no test anywhere. It is the live
  alert feed, it takes a user id straight from the path, and a mistake here
  streams one woman's emergencies to another account in real time. The guard
  exists and is correct; nothing was proving it stays correct.

* **`POST /api/v1/devices/{device_id}/heartbeat`** is a write. Reaching another
  account's device would let an attacker forge battery level and last-seen,
  which is how the app decides whether a wearable is still watching -- a glove
  reported healthy while its owner is out of range is a silent failure of the
  thing this product exists to do.

`TestRouteRegistry` then makes the absence itself fail: a new route carrying an
id has to be classified here before the suite goes green, so the next one
cannot slip past unnoticed the way these two did.

**On driving the websocket by hand.** Starlette's `TestClient` cannot be used
in this repo -- it passes `app=` to `httpx.Client`, which the installed httpx
removed -- which is why every suite here builds an `httpx.ASGITransport`
instead. There is no equivalent transport for websockets, so `_ws_exchange`
speaks the ASGI websocket protocol to the app directly. That is a closer test
than a client library would give: it observes exactly what the handler sends,
including a `websocket.close` sent *instead of* an accept, which is how this
route rejects an impostor.
"""

import re
import unittest
from uuid import uuid4

import httpx

from fastapi_app.db import init_db
from fastapi_app.main import app

DENIED = (401, 403, 404)


async def _ws_exchange(path: str, query: str, to_send: list[str] | None = None) -> list[dict]:
    """Open an ASGI websocket to `app` and return everything it sent back.

    Returns the raw ASGI messages, so a caller can tell the difference between
    "accepted, then replied" and "closed during the handshake".
    """
    incoming: list[dict] = [{"type": "websocket.connect"}]
    for text in to_send or []:
        incoming.append({"type": "websocket.receive", "text": text})
    incoming.append({"type": "websocket.disconnect", "code": 1000})

    sent: list[dict] = []
    queue = list(incoming)

    async def receive():
        if queue:
            return queue.pop(0)
        return {"type": "websocket.disconnect", "code": 1000}

    async def send(message):
        sent.append(message)

    scope = {
        "type": "websocket",
        "asgi": {"version": "3.0", "spec_version": "2.3"},
        "http_version": "1.1",
        "scheme": "ws",
        "server": ("testserver", 80),
        "client": ("127.0.0.1", 50000),
        "root_path": "",
        "path": path,
        "raw_path": path.encode(),
        "query_string": query.encode(),
        "headers": [(b"host", b"testserver")],
        "subprotocols": [],
        "state": {},
    }

    await app(scope, receive, send)
    return sent


def _accepted(messages: list[dict]) -> bool:
    return any(m["type"] == "websocket.accept" for m in messages)


def _texts(messages: list[dict]) -> list[str]:
    return [m["text"] for m in messages if m.get("type") == "websocket.send" and "text" in m]


class _TwoAccounts(unittest.IsolatedAsyncioTestCase):
    """Two real accounts driven through the ASGI app."""

    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self.a_id, self.a_token = await self._register()
        self.b_id, self.b_token = await self._register()
        self.a = {"Authorization": f"Bearer {self.a_token}"}
        self.b = {"Authorization": f"Bearer {self.b_token}"}

    async def asyncTearDown(self):
        await self.client.aclose()

    async def _register(self) -> tuple[str, str]:
        email = f"rt-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Realtime Test",
                "phone": "+15550100000",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        self.assertEqual(login.status_code, 200, login.text)
        token = login.json()["access_token"]
        me = await self.client.get(
            "/api/v1/users/me", headers={"Authorization": f"Bearer {token}"}
        )
        self.assertEqual(me.status_code, 200, me.text)
        return me.json()["id"], token


class TestAlertStreamIsolation(_TwoAccounts):
    """A user id in a path is an assertion, never a permission."""

    async def test_the_owner_can_open_her_own_stream(self):
        # The control. A test that only proved connections fail would pass just
        # as happily against a feed that is broken for everyone.
        sent = await _ws_exchange(
            f"/api/v1/ws/alerts/{self.a_id}", f"token={self.a_token}", ["ping"]
        )

        self.assertTrue(_accepted(sent), f"the owner was refused her own feed: {sent}")
        self.assertIn("pong", _texts(sent))

    async def test_b_cannot_open_a_stream(self):
        sent = await _ws_exchange(
            f"/api/v1/ws/alerts/{self.a_id}", f"token={self.b_token}", ["ping"]
        )

        self.assertFalse(
            _accepted(sent),
            "another account was handed a live feed of someone's emergencies",
        )
        self.assertNotIn("pong", _texts(sent))

    async def test_a_garbage_token_is_refused(self):
        sent = await _ws_exchange(
            f"/api/v1/ws/alerts/{self.a_id}", "token=not-a-token", ["ping"]
        )

        self.assertFalse(_accepted(sent))

    async def test_a_refresh_token_cannot_open_the_feed(self):
        # The handler decodes with `expected_type="access"`. Without that, the
        # 30-day refresh token would be a month-long key to the live feed.
        email = f"rt-{uuid4().hex}@safeherapp.com"
        await self.client.post(
            "/api/v1/auth/register",
            json={
                "email": email,
                "password": "TestPass123!",
                "full_name": "Refresh Test",
                "phone": "+15550100000",
            },
        )
        login = await self.client.post(
            "/api/v1/auth/login", json={"email": email, "password": "TestPass123!"}
        )
        body = login.json()
        refresh = body.get("refresh_token")
        if not refresh:
            self.skipTest("this build does not issue a refresh token on login")

        me = await self.client.get(
            "/api/v1/users/me",
            headers={"Authorization": f"Bearer {body['access_token']}"},
        )
        sent = await _ws_exchange(
            f"/api/v1/ws/alerts/{me.json()['id']}", f"token={refresh}", ["ping"]
        )

        self.assertFalse(_accepted(sent), "a refresh token opened the live alert feed")

    async def test_no_token_at_all_is_refused(self):
        sent = await _ws_exchange(f"/api/v1/ws/alerts/{self.a_id}", "", ["ping"])

        self.assertFalse(_accepted(sent))


class TestDeviceHeartbeatIsolation(_TwoAccounts):
    async def _device_of_a(self) -> str:
        response = await self.client.post(
            "/api/v1/devices/register",
            json={
                "device_name": f"A's glove {uuid4().hex[:8]}",
                "device_type": "smart_glove",
            },
            headers=self.a,
        )
        self.assertIn(response.status_code, (200, 201), response.text)
        return response.json()["id"]

    async def test_b_cannot_write_a_heartbeat_to_a_device(self):
        device_id = await self._device_of_a()
        response = await self.client.post(
            f"/api/v1/devices/{device_id}/heartbeat",
            json={"battery_level": 3, "signal_strength": 5},
            headers=self.b,
        )
        self.assertIn(response.status_code, DENIED, response.text)

    async def test_the_forged_reading_did_not_land(self):
        # The check that matters. A 404 that had already written the row would
        # be a test passing over a live bug.
        device_id = await self._device_of_a()
        await self.client.post(
            f"/api/v1/devices/{device_id}/heartbeat",
            json={"battery_level": 3, "signal_strength": 5},
            headers=self.b,
        )

        listing = await self.client.get("/api/v1/devices/me", headers=self.a)
        self.assertEqual(listing.status_code, 200, listing.text)
        device = next(d for d in listing.json() if d["id"] == device_id)
        self.assertNotEqual(
            device.get("battery_level"),
            3,
            "another account wrote a battery level onto this device",
        )

    async def test_the_owner_can_write_her_own_heartbeat(self):
        device_id = await self._device_of_a()
        response = await self.client.post(
            f"/api/v1/devices/{device_id}/heartbeat",
            json={"battery_level": 77, "signal_strength": 80},
            headers=self.a,
        )
        self.assertEqual(response.status_code, 204, response.text)


class TestRouteRegistry(unittest.TestCase):
    """Every route carrying an id must be a decision someone made.

    The two gaps above existed because nothing noticed them. This turns that
    into a failing test: add a route with a path parameter and the suite stops
    until it is listed below with how it is protected.

    `OWNER` means the handler re-derives ownership from the token and an
    isolation test proves it. `TOKEN` means the path segment *is* the
    credential -- an unguessable share token -- and is unauthenticated on
    purpose.
    """

    OWNER = "owner-checked, covered by an isolation test"
    TOKEN = "token is the credential, covered by test_incident_shares"

    REGISTRY = {
        "/api/v1/alerts/emergency/{}/dispatch": OWNER,
        "/api/v1/devices/{}": OWNER,
        "/api/v1/devices/{}/heartbeat": OWNER,
        "/api/v1/incidents/{}": OWNER,
        "/api/v1/incidents/{}/report.pdf": OWNER,
        "/api/v1/incidents/{}/share": OWNER,
        "/api/v1/incidents/{}/shares": OWNER,
        "/api/v1/incidents/{}/shares/{}": OWNER,
        "/api/v1/incidents/{}/summary": OWNER,
        "/api/v1/journeys/{}/arrive": OWNER,
        "/api/v1/journeys/{}/cancel": OWNER,
        "/api/v1/journeys/{}/check-in": OWNER,
        "/api/v1/journeys/{}/escalate": OWNER,
        "/api/v1/journeys/{}/locations": OWNER,
        "/api/v1/media/evidence/incident/{}/list": OWNER,
        "/api/v1/media/evidence/{}": OWNER,
        "/api/v1/share/{}": TOKEN,
        "/api/v1/share/{}/evidence/{}": TOKEN,
        "/api/v1/users/me/emergency-contacts/{}": OWNER,
        "/api/v1/users/me/emergency-contacts/{}/verify": OWNER,
        "/api/v1/users/me/emergency-contacts/{}/verify/send": OWNER,
        "/api/v1/ws/alerts/{}": OWNER,
    }

    @staticmethod
    def _id_bearing_routes() -> set:
        found = set()
        for route in app.routes:
            path = getattr(route, "path", "")
            if "{" in path and path.startswith("/api/v1"):
                found.add(re.sub(r"\{[^}]*\}", "{}", path))
        return found

    def test_the_sweep_actually_finds_routes(self):
        # Guards the guard: a selector that matched nothing would make both
        # tests below pass vacuously.
        self.assertGreaterEqual(len(self._id_bearing_routes()), 20)

    def test_every_id_bearing_route_is_classified(self):
        unlisted = sorted(self._id_bearing_routes() - set(self.REGISTRY))

        self.assertEqual(
            unlisted,
            [],
            "a route takes an id from the client and nothing here says how it is "
            "protected. Add an isolation test, then list it in REGISTRY",
        )

    def test_the_registry_names_no_route_that_is_gone(self):
        # The other direction: a stale entry would quietly hand a deleted
        # route's exemption to whatever later claims its path.
        stale = sorted(set(self.REGISTRY) - self._id_bearing_routes())

        self.assertEqual(stale, [], "REGISTRY lists routes that no longer exist")

    def test_only_share_links_are_unauthenticated(self):
        # Guards the exemption itself. `TOKEN` skips the signed-in check, so it
        # must never spread beyond the two routes designed for it.
        exempt = sorted(p for p, why in self.REGISTRY.items() if why == self.TOKEN)

        self.assertEqual(
            exempt,
            ["/api/v1/share/{}", "/api/v1/share/{}/evidence/{}"],
        )


if __name__ == "__main__":
    unittest.main()
