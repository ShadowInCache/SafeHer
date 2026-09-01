"""The one authenticated route that emails a stranger.

`POST /users/me/emergency-contacts/{id}/verify/send` sends a code to an address
the *caller* chose. Every other mail-sending route -- register, resend
verification, password reset -- carries a rate limit. This one did not, because
the action sits past a path parameter and no prefix rule reached it.

Unlimited, an account can add any address as a "contact" and loop this endpoint
to bomb that inbox from SafeHer's own verified sender. The cost lands in three
places at once: the victim's mailbox, the operator's delivery credits, and the
sending domain's reputation -- and the third one is the expensive one, because
a domain marked as a spam source stops delivering the emergency alerts this
whole system exists to send.

These tests pin the limit, and pin that it did not spread to the routes next to
it: throttling someone's ability to *read* their own contact list during an
emergency would be a worse bug than the one being fixed.
"""

import unittest

from fastapi_app.rate_limit import DEFAULT_RULES, RateLimitRule, SlidingWindowLimiter

SEND = "/api/v1/users/me/emergency-contacts/contact-abc/verify/send"
LIST = "/api/v1/users/me/emergency-contacts"
CONFIRM = "/api/v1/users/me/emergency-contacts/contact-abc/verify"


class TestVerificationSendIsLimited(unittest.TestCase):
    def setUp(self):
        self.limiter = SlidingWindowLimiter(DEFAULT_RULES)

    def test_the_send_route_is_covered_by_a_rule(self):
        rule = self.limiter.rule_for(SEND)

        self.assertIsNotNone(
            rule,
            "the only route that emails an address the caller picked must be limited",
        )
        self.assertLessEqual(rule.limit, 20, "a limit this high is not a limit")

    def test_it_refuses_once_the_hourly_allowance_is_spent(self):
        rule = self.limiter.rule_for(SEND)

        for i in range(rule.limit):
            self.assertIsNone(
                self.limiter.check("1.2.3.4", SEND, now=100.0 + i),
                f"send {i + 1} should be allowed",
            )

        retry = self.limiter.check("1.2.3.4", SEND, now=100.0 + rule.limit)
        self.assertIsNotNone(retry, "the mail bomb has to stop somewhere")
        self.assertGreater(retry, 0)

    def test_reading_the_contact_list_is_not_throttled(self):
        # The blast radius check. Someone in an emergency may open their
        # contacts repeatedly; a limit that caught this route too would take a
        # working safety feature away to fix an abuse problem elsewhere.
        for i in range(50):
            self.limiter.check("1.2.3.4", SEND, now=100.0 + i)

        self.assertIsNone(
            self.limiter.rule_for(LIST),
            "the fix must not spread to ordinary contact management",
        )
        self.assertIsNone(self.limiter.check("1.2.3.4", LIST, now=200.0))

    def test_entering_a_received_code_is_not_throttled_by_this_rule(self):
        # `/verify` and `/verify/send` differ by one segment. A suffix rule that
        # matched both would lock a user out of confirming a code she already
        # has, which sends her back to the endpoint that is actually limited.
        self.assertIsNone(self.limiter.rule_for(CONFIRM))

    def test_one_abuser_does_not_lock_out_everyone_else(self):
        rule = self.limiter.rule_for(SEND)
        for i in range(rule.limit + 5):
            self.limiter.check("1.2.3.4", SEND, now=100.0 + i)

        self.assertIsNone(self.limiter.check("5.6.7.8", SEND, now=200.0))


class TestSuffixRulesKeepSeparateCounters(unittest.TestCase):
    """Two rules sharing a prefix must not share a bucket.

    Before `suffix` existed, a rule's identity was its prefix alone. Keying the
    counter on the prefix now would let traffic to one route exhaust the
    allowance of an unrelated one that happens to sit beneath it.
    """

    def test_rules_on_the_same_prefix_are_counted_independently(self):
        limiter = SlidingWindowLimiter(
            [
                RateLimitRule("/api/v1/x", limit=2, window_seconds=60, suffix="/send"),
                RateLimitRule("/api/v1/x", limit=2, window_seconds=60, suffix="/other"),
            ]
        )

        limiter.check("1.2.3.4", "/api/v1/x/a/send", now=100.0)
        limiter.check("1.2.3.4", "/api/v1/x/a/send", now=101.0)
        self.assertIsNotNone(limiter.check("1.2.3.4", "/api/v1/x/a/send", now=102.0))

        self.assertIsNone(
            limiter.check("1.2.3.4", "/api/v1/x/a/other", now=103.0),
            "a spent allowance on one route must not spend another's",
        )

    def test_the_most_specific_rule_wins(self):
        limiter = SlidingWindowLimiter(
            [
                RateLimitRule("/api/v1/x", limit=100, window_seconds=60),
                RateLimitRule("/api/v1/x", limit=2, window_seconds=60, suffix="/send"),
            ]
        )

        self.assertEqual(limiter.rule_for("/api/v1/x/a/send").limit, 2)
        self.assertEqual(limiter.rule_for("/api/v1/x/a/read").limit, 100)


if __name__ == "__main__":
    unittest.main()
