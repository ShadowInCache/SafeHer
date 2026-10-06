"""The busiest endpoint in the product is keyed by account, not by address.

`/alerts/analyze` had no rate limit at all, and adding a naive one would have
done harm. An armed Safe Journey posts once a second — sixty requests a minute,
legitimately — and mobile carriers put thousands of subscribers behind one NAT
address. Keyed by address, any limit loose enough for several women travelling
at once is no limit, and any limit tight enough to matter throttles real
journeys. So the identity had to change before the rule could exist.

The subject is read from a *verified* token. Unverified it would be worse than
useless: anyone could mint a different `sub` per request and walk through the
limiter it exists to enforce.
"""

import unittest
from types import SimpleNamespace

from fastapi_app.config import get_settings
from fastapi_app.rate_limit import (
    DEFAULT_RULES,
    SlidingWindowLimiter,
    client_key,
)
from fastapi_app.security import create_access_token


def _request(headers=None, host="203.0.113.7"):
    return SimpleNamespace(
        headers=headers or {},
        client=SimpleNamespace(host=host),
    )


class ClientKeyTests(unittest.TestCase):
    def setUp(self):
        self.settings = get_settings()

    def _token(self, subject):
        return create_access_token(
            subject=subject, role="user", settings=self.settings
        )

    def test_an_anonymous_caller_is_keyed_by_address(self):
        # Sign-in and registration have no account to key on by definition.
        self.assertEqual(client_key(_request()), "203.0.113.7")

    def test_the_first_forwarded_hop_wins(self):
        # The rest is client-supplied; appending to it would be a trivial
        # evasion of an address-keyed limit.
        request = _request({"x-forwarded-for": "198.51.100.5, 10.0.0.1"})
        self.assertEqual(client_key(request), "198.51.100.5")

    def test_an_authenticated_caller_is_keyed_by_account(self):
        request = _request({"authorization": f"Bearer {self._token('user-a')}"})
        self.assertEqual(client_key(request), "user:user-a")

    def test_two_accounts_behind_one_address_get_separate_buckets(self):
        # The whole point. Carrier NAT would otherwise make one woman's journey
        # consume another's allowance.
        a = _request({"authorization": f"Bearer {self._token('user-a')}"})
        b = _request({"authorization": f"Bearer {self._token('user-b')}"})

        self.assertNotEqual(client_key(a), client_key(b))

    def test_one_account_from_two_addresses_shares_a_bucket(self):
        # Switching from WiFi to mobile data must not reset the allowance.
        token = self._token("user-a")
        wifi = _request({"authorization": f"Bearer {token}"}, host="192.0.2.1")
        cell = _request({"authorization": f"Bearer {token}"}, host="198.51.100.9")

        self.assertEqual(client_key(wifi), client_key(cell))

    def test_a_forged_subject_cannot_mint_a_fresh_bucket(self):
        # An unverified `sub` would let anyone evade the limiter by changing it
        # each request. A token we did not sign falls back to the address.
        forged = (
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJzdWIiOiJ2aWN0aW0iLCJ0eXBlIjoiYWNjZXNzIn0.not-a-real-signature"
        )
        request = _request({"authorization": f"Bearer {forged}"})

        self.assertEqual(client_key(request), "203.0.113.7")

    def test_a_malformed_header_falls_back_rather_than_raising(self):
        # This runs in middleware ahead of routing: raising here would turn an
        # authentication problem into a rate-limit error and tell the caller
        # the wrong thing about their own request.
        for header in ("", "Bearer", "Bearer    ", "Basic abc123", "garbage"):
            with self.subTest(header=header):
                request = _request({"authorization": header})
                self.assertEqual(client_key(request), "203.0.113.7")


class AnalyzeRuleTests(unittest.TestCase):
    def setUp(self):
        self.limiter = SlidingWindowLimiter(DEFAULT_RULES)

    def test_the_fusion_endpoint_has_a_rule(self):
        rule = self.limiter.rule_for("/api/v1/alerts/analyze")
        self.assertIsNotNone(rule, "the busiest endpoint had no limit at all")

    def test_a_real_journey_is_not_throttled(self):
        # One post a second for five minutes, which is an ordinary journey.
        rule = self.limiter.rule_for("/api/v1/alerts/analyze")
        self.assertGreaterEqual(
            rule.limit / rule.window_seconds,
            1.0,
            "a journey posts at 1 Hz; a limit below that throttles correct use",
        )

    def test_a_runaway_client_is_eventually_stopped(self):
        rule = self.limiter.rule_for("/api/v1/alerts/analyze")
        now = 1000.0
        blocked = None
        for i in range(rule.limit + 50):
            retry = self.limiter.check(
                "user:runaway", "/api/v1/alerts/analyze", now=now + i * 0.01
            )
            if retry is not None:
                blocked = i
                break

        self.assertIsNotNone(blocked, "an unbounded client was never stopped")
        self.assertGreaterEqual(blocked, rule.limit)

    def test_one_account_hitting_its_limit_does_not_affect_another(self):
        rule = self.limiter.rule_for("/api/v1/alerts/analyze")
        now = 2000.0
        for i in range(rule.limit + 10):
            self.limiter.check("user:noisy", "/api/v1/alerts/analyze", now=now + i * 0.01)

        self.assertIsNone(
            self.limiter.check("user:quiet", "/api/v1/alerts/analyze", now=now + 1),
            "one account must not consume another's allowance",
        )


if __name__ == "__main__":
    unittest.main()
