"""Per-client rate limiting for abuse-prone endpoints.

**What this defends and what it does not.** Sign-in already has a per-account
lockout (`auth_security.register_failed_login`), which stops someone guessing
one person's password. It does nothing about the other shapes of abuse against
the same endpoints: spraying one common password across many accounts, farming
sign-ups, or hammering the OTP and password-reset routes -- each of which sends
real email and costs real money. It also does nothing about SOS dispatch, where
a flood would fan out messages to real contacts.

This adds a second, orthogonal limit keyed by client address rather than by
account.

**Honest limitations, because a security control that is trusted beyond its
reach is worse than none:**

* The window is held in process memory. Behind more than one worker or
  instance the effective limit is multiplied by the instance count. It raises
  the cost of abuse; it is not a distributed quota. A shared Redis counter is
  the upgrade, and Redis is already a dependency of the deployment.
* The client is identified by `X-Forwarded-For` when present, falling back to
  the socket address. `X-Forwarded-For` is caller-controlled and only
  trustworthy behind a proxy that overwrites it. Render does. A direct-to-app
  deployment would let an attacker rotate the header and evade this.
* IPv4 addresses are shared by whole networks, so a limit low enough to be
  strict would lock out an entire office or campus. The limits here are
  deliberately generous enough to be safe for shared egress.
"""

from __future__ import annotations

import time
from collections import defaultdict, deque
from dataclasses import dataclass
from typing import Deque, Dict, Iterable, Optional, Tuple


@dataclass(frozen=True)
class RateLimitRule:
    """`limit` requests allowed per `window_seconds`, for paths under `prefix`.

    An optional `suffix` narrows the rule to paths that also *end* a given
    way. Prefix alone cannot express the routes that matter most here: the
    expensive action often sits past a path parameter, as in
    `/users/me/emergency-contacts/{contact_id}/verify/send`, and a prefix wide
    enough to catch it would also throttle reading the contact list.
    """

    prefix: str
    limit: int
    window_seconds: int
    suffix: str = ""

    @property
    def key(self) -> str:
        """Identity of this rule's counter. Two rules sharing a prefix but
        differing in suffix must not share a bucket."""
        return self.prefix + "|" + self.suffix

    def matches(self, path: str) -> bool:
        return path.startswith(self.prefix) and path.endswith(self.suffix)

    @property
    def specificity(self) -> int:
        return len(self.prefix) + len(self.suffix)


class SlidingWindowLimiter:
    """Counts recent hits per (client, rule) and reports when one is over.

    A sliding window rather than a fixed one: a fixed window lets an attacker
    send `limit` requests at the end of one window and `limit` again at the
    start of the next, doubling the intended rate at the boundary.
    """

    def __init__(self, rules: Iterable[RateLimitRule]) -> None:
        # Most specific first, so a narrow rule beats a general one.
        self._rules = sorted(rules, key=lambda r: r.specificity, reverse=True)
        self._hits: Dict[Tuple[str, str], Deque[float]] = defaultdict(deque)

    def rule_for(self, path: str) -> Optional[RateLimitRule]:
        for rule in self._rules:
            if rule.matches(path):
                return rule
        return None

    def check(self, client: str, path: str, *, now: Optional[float] = None) -> Optional[int]:
        """Record a hit. Returns None if allowed, else seconds to wait."""
        rule = self.rule_for(path)
        if rule is None:
            return None

        now = time.monotonic() if now is None else now
        bucket = self._hits[(client, rule.key)]

        cutoff = now - rule.window_seconds
        while bucket and bucket[0] <= cutoff:
            bucket.popleft()

        if len(bucket) >= rule.limit:
            # Oldest hit in the window decides when a slot frees up.
            return max(1, int(bucket[0] + rule.window_seconds - now) + 1)

        bucket.append(now)
        return None

    def reset(self) -> None:
        self._hits.clear()


def client_key(request) -> str:
    """Best available identifier for the caller.

    **An authenticated caller is keyed by account, not by address**, and the
    difference decides whether a limit is usable at all on this product's
    busiest endpoint. An armed Safe Journey posts to `/alerts/analyze` once a
    second -- sixty requests a minute, legitimately -- and mobile networks put
    thousands of subscribers behind one carrier-NAT address. Keyed by address,
    any limit loose enough for several women travelling at once is no limit,
    and any limit tight enough to matter throttles real journeys.

    The subject comes from a *verified* token. Reading it unverified would be
    worse than useless here: anyone could mint a different `sub` per request
    and walk straight through the limiter, which is exactly what it exists to
    stop. Verification costs one HMAC over a short string.

    Unauthenticated routes -- sign-in, registration, password reset, where the
    caller has no account yet by definition -- still key by address, which is
    the only identity they have.

    Only the first `X-Forwarded-For` hop is used; the rest is client-supplied
    and appending to it is a trivial evasion.
    """
    subject = _authenticated_subject(request)
    if subject is not None:
        return f"user:{subject}"

    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    client = getattr(request, "client", None)
    return getattr(client, "host", None) or "unknown"


def _authenticated_subject(request) -> Optional[str]:
    """The account id from a valid bearer token, or None.

    Every failure is None rather than an exception: this runs in middleware
    ahead of routing, so a malformed or expired token must fall through to
    address-based limiting and let the endpoint's own dependency produce the
    401. Rejecting here would turn an authentication error into a rate-limit
    error, and the caller would be told the wrong thing about their own
    request.
    """
    header = request.headers.get("authorization") or ""
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None

    try:
        # Imported lazily: `security` imports settings and schemas, and this
        # module is deliberately importable on its own.
        from fastapi_app.config import get_settings
        from fastapi_app.security import decode_token

        return decode_token(token.strip(), get_settings()).sub
    except Exception:
        return None


# Deliberately generous: these exist to make automated abuse expensive, not to
# police normal use. A person signing in a dozen times in five minutes is
# having a bad day, not attacking anything.
DEFAULT_RULES = (
    # Sign-in: per-account lockout already covers guessing one password, so
    # this is aimed at spraying one password across many accounts.
    RateLimitRule("/api/v1/auth/login", limit=20, window_seconds=300),
    # Each of these sends mail. Cheap for the attacker, not for the operator.
    RateLimitRule("/api/v1/auth/register", limit=10, window_seconds=3600),
    RateLimitRule("/api/v1/auth/resend-verification", limit=6, window_seconds=3600),
    RateLimitRule("/api/v1/auth/verify-email", limit=20, window_seconds=900),
    RateLimitRule("/api/v1/auth/password-reset", limit=6, window_seconds=3600),
    # SOS fans out to real contacts. The limit is high enough that a genuine
    # repeat emergency is never blocked -- someone in trouble may well press
    # it several times -- and low enough that a script cannot spam a contact
    # list indefinitely.
    RateLimitRule("/api/v1/alerts/emergency", limit=30, window_seconds=600),
    # Each frame runs YOLOv8n on the server's CPU, which is the most expensive
    # thing an authenticated caller can ask for. The limit suits the sampled
    # web fallback -- roughly one frame every two seconds for ten minutes --
    # and refuses a client looping it as free GPU-less inference.
    RateLimitRule("/api/v1/alerts/weapon-frame", limit=300, window_seconds=600),
    # The busiest authenticated endpoint in the product: an armed Safe Journey
    # posts once a second for its whole duration. 300 in 60s is five times the
    # legitimate rate, which leaves generous room for a retry storm or a clock
    # skew while still capping a client stuck in a loop.
    #
    # This is only safe because `client_key` keys authenticated callers by
    # account. Keyed by address it would have throttled several women behind
    # one carrier NAT, which is why the endpoint previously had no rule at all.
    RateLimitRule("/api/v1/alerts/analyze", limit=300, window_seconds=60),
    # Emails a code to an address the *caller* chose, which makes it the one
    # authenticated route that can send mail to a stranger. Without a limit,
    # an account can add any address as a "contact" and loop this endpoint to
    # bomb that inbox from SafeHer's verified sender -- burning delivery
    # credits and the sending domain's reputation along with it. Every other
    # mail-sending route above was limited; this one was missed because the
    # action sits past a path parameter and no prefix reached it.
    #
    # Twelve in an hour is far above real use: a contact is verified once,
    # and a resend or two covers a code that went to spam.
    RateLimitRule(
        "/api/v1/users/me/emergency-contacts",
        limit=12,
        window_seconds=3600,
        suffix="/verify/send",
    ),
)
