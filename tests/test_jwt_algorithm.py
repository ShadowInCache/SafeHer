"""Every token this app issues is HS256, and nothing else is accepted.

Two reasons this is pinned rather than left as an implementation detail.

**It is a live security property.** Accepting more than one algorithm is how
algorithm-confusion attacks work: a token whose header says `none`, or one
signed with HMAC using an RSA *public* key as the secret, gets verified against
a key the attacker already has. `python-jose` 3.3.0 shipped exactly that class
of bug (CVE-2024-33663), which is part of why the pin moved to 3.4.0.

**A dependency decision rests on it.** python-jose declares `pyasn1<0.5.0`, and
0.4.x carries known vulnerabilities and conflicts with pyasn1-modules. This
project deliberately holds the newer, safe `pyasn1` instead, which is sound
*only* because pyasn1 is reached when parsing asymmetric keys and HS256 never
does. If this app ever moves to RS256 or ES256, that reasoning collapses and
the pin has to be revisited -- so the assumption is asserted here rather than
written down and forgotten.
"""

import base64
import json
import time
import unittest

from jose import jwt


def _b64url(raw: bytes) -> str:
    """Base64url without padding, as JWT requires."""
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

from fastapi_app.config import get_settings
from fastapi_app.security import (
    create_access_token,
    create_refresh_token,
    create_ws_ticket,
    decode_token,
)


class JwtAlgorithmTests(unittest.TestCase):
    def setUp(self):
        self.settings = get_settings()

    def _issued(self):
        return {
            "access": create_access_token(
                subject="u1", role="user", settings=self.settings
            ),
            "refresh": create_refresh_token(
                subject="u1", role="user", settings=self.settings
            ),
            "ws ticket": create_ws_ticket(
                subject="u1", role="user", settings=self.settings
            ),
        }

    def test_every_issued_token_is_hs256(self):
        for name, token in self._issued().items():
            with self.subTest(token=name):
                self.assertEqual(jwt.get_unverified_header(token)["alg"], "HS256")

    def test_a_normal_token_still_verifies(self):
        # The negatives below prove nothing if the positive path is broken.
        token = create_access_token(subject="u1", role="user", settings=self.settings)
        self.assertEqual(decode_token(token, self.settings).sub, "u1")

    def test_an_unsigned_token_is_refused(self):
        # The `alg: none` attack. A token with no signature at all must not be
        # honoured just because its claims look right.
        #
        # Assembled by hand rather than with `jwt.encode`, which refuses to
        # produce one ("Algorithm none not supported"). That refusal is a
        # property of *this* library, and an attacker is not obliged to use it —
        # what has to be tested is that our decode path rejects the bytes.
        header = _b64url(json.dumps({"alg": "none", "typ": "JWT"}).encode())
        claims = _b64url(
            json.dumps(
                {
                    "sub": "victim",
                    "role": "admin",
                    "type": "access",
                    "exp": int(time.time()) + 3600,
                    "aud": self.settings.jwt_audience,
                    "iss": self.settings.jwt_issuer,
                }
            ).encode()
        )
        forged = f"{header}.{claims}."

        with self.assertRaises(Exception):
            decode_token(forged, self.settings)

    def test_a_token_signed_with_another_algorithm_is_refused(self):
        # Same secret, different algorithm. `decode` pins `algorithms=["HS256"]`,
        # so this must fail even though the key is correct.
        forged = jwt.encode(
            {"sub": "victim", "role": "admin", "type": "access"},
            self.settings.jwt_secret_key,
            algorithm="HS512",
        )
        with self.assertRaises(Exception):
            decode_token(forged, self.settings)

    def test_a_token_signed_with_the_wrong_secret_is_refused(self):
        forged = jwt.encode(
            {"sub": "victim", "role": "admin", "type": "access"},
            "not-the-signing-key",
            algorithm="HS256",
        )
        with self.assertRaises(Exception):
            decode_token(forged, self.settings)

    def test_a_refresh_token_cannot_be_used_as_an_access_token(self):
        # Token type is part of the contract: a refresh token is longer-lived,
        # so accepting one as an access token would silently extend every
        # session well past its intended life.
        refresh = create_refresh_token(subject="u1", role="user", settings=self.settings)
        with self.assertRaises(Exception):
            decode_token(refresh, self.settings, expected_type="access")


if __name__ == "__main__":
    unittest.main()
