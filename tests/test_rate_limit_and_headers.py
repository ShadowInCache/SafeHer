"""Rate limiting and security-header tests.

The limiter is switched off in development so that the suite (and local work)
can create accounts freely, which means it would otherwise ship untested. These
tests exercise the limiter directly, and then force it on to prove the
middleware actually returns 429 and that a normal request is untouched.
"""

import unittest
from uuid import uuid4

import httpx

import fastapi_app.main as main_module
from fastapi_app.db import init_db
from fastapi_app.main import app
from fastapi_app.rate_limit import RateLimitRule, SlidingWindowLimiter, client_key


class TestSlidingWindowLimiter(unittest.TestCase):
    def setUp(self):
        self.limiter = SlidingWindowLimiter(
            [RateLimitRule("/api/v1/auth/login", limit=3, window_seconds=60)]
        )

    def test_allows_up_to_the_limit_then_refuses(self):
        for i in range(3):
            self.assertIsNone(
                self.limiter.check("1.2.3.4", "/api/v1/auth/login", now=100.0 + i),
                f"request {i + 1} should be allowed",
            )
        retry = self.limiter.check("1.2.3.4", "/api/v1/auth/login", now=103.0)
        self.assertIsNotNone(retry)
        self.assertGreater(retry, 0)

    def test_clients_are_counted_separately(self):
        for i in range(3):
            self.limiter.check("1.2.3.4", "/api/v1/auth/login", now=100.0 + i)

        self.assertIsNone(
            self.limiter.check("5.6.7.8", "/api/v1/auth/login", now=103.0),
            "one attacker must not lock everyone else out",
        )

    def test_the_window_slides(self):
        for i in range(3):
            self.limiter.check("1.2.3.4", "/api/v1/auth/login", now=100.0 + i)
        self.assertIsNotNone(self.limiter.check("1.2.3.4", "/api/v1/auth/login", now=103.0))

        # Once the oldest hits age out, capacity returns.
        self.assertIsNone(self.limiter.check("1.2.3.4", "/api/v1/auth/login", now=161.0))

    def test_unlisted_paths_are_never_limited(self):
        for i in range(500):
            self.assertIsNone(
                self.limiter.check("1.2.3.4", "/api/v1/incidents/", now=100.0 + i)
            )

    def test_longest_matching_prefix_wins(self):
        limiter = SlidingWindowLimiter(
            [
                RateLimitRule("/api/v1", limit=100, window_seconds=60),
                RateLimitRule("/api/v1/auth/login", limit=1, window_seconds=60),
            ]
        )
        self.assertIsNone(limiter.check("c", "/api/v1/auth/login", now=1.0))
        self.assertIsNotNone(
            limiter.check("c", "/api/v1/auth/login", now=2.0),
            "the specific login rule must beat the general one",
        )

    def test_forwarded_header_takes_only_the_first_hop(self):
        class _Req:
            headers = {"x-forwarded-for": "9.9.9.9, 10.0.0.1, 172.16.0.1"}
            client = None

        self.assertEqual(client_key(_Req()), "9.9.9.9")

    def test_falls_back_to_socket_address(self):
        class _Client:
            host = "203.0.113.5"

        class _Req:
            headers = {}
            client = _Client()

        self.assertEqual(client_key(_Req()), "203.0.113.5")


class TestMiddleware(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        await init_db()
        self.client = httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://testserver"
        )
        self._was_enabled = main_module.rate_limiting_enabled
        self._original = main_module.rate_limiter

    async def asyncTearDown(self):
        main_module.rate_limiting_enabled = self._was_enabled
        main_module.rate_limiter = self._original
        await self.client.aclose()

    async def test_security_headers_are_present_on_every_response(self):
        response = await self.client.get("/api/v1/health")

        self.assertEqual(response.headers.get("X-Content-Type-Options"), "nosniff")
        self.assertEqual(response.headers.get("X-Frame-Options"), "DENY")
        self.assertEqual(response.headers.get("Referrer-Policy"), "no-referrer")
        self.assertIn("frame-ancestors 'none'", response.headers.get("Content-Security-Policy", ""))

    async def test_login_is_throttled_once_enabled(self):
        main_module.rate_limiter = SlidingWindowLimiter(
            [RateLimitRule("/api/v1/auth/login", limit=2, window_seconds=300)]
        )
        main_module.rate_limiting_enabled = True

        payload = {"email": f"rl-{uuid4().hex}@safeherapp.com", "password": "whatever"}
        first = await self.client.post("/api/v1/auth/login", json=payload)
        second = await self.client.post("/api/v1/auth/login", json=payload)
        third = await self.client.post("/api/v1/auth/login", json=payload)

        self.assertNotEqual(first.status_code, 429)
        self.assertNotEqual(second.status_code, 429)
        self.assertEqual(third.status_code, 429, third.text)
        self.assertIn("Retry-After", third.headers)

    async def test_throttling_does_not_leak_onto_unrelated_routes(self):
        main_module.rate_limiter = SlidingWindowLimiter(
            [RateLimitRule("/api/v1/auth/login", limit=1, window_seconds=300)]
        )
        main_module.rate_limiting_enabled = True

        payload = {"email": f"rl-{uuid4().hex}@safeherapp.com", "password": "whatever"}
        await self.client.post("/api/v1/auth/login", json=payload)
        await self.client.post("/api/v1/auth/login", json=payload)

        health = await self.client.get("/api/v1/health")
        self.assertEqual(health.status_code, 200, "health must not be collateral damage")


if __name__ == "__main__":
    unittest.main()
