"""Where FCM's service account comes from — SRS FR-EMG-04.

A file path works on a developer machine, where the credential is gitignored
and stays out of the repository. It does not work on a host with an
ephemeral filesystem and nothing to copy the file from, which is every
managed platform — the first Render deploy would have reported push as
unconfigured with no indication why.

So the same credential also travels as an environment variable. These tests
pin which source wins, and what happens when one of them is malformed —
because a corrupted private key does not fail at startup, it fails much
later inside an emergency dispatch with a signature error that names
nothing useful.
"""

from __future__ import annotations

import base64
import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

os.environ["DATABASE_URL"] = "sqlite:///./test_safeher.db"
os.environ["ENABLE_MQTT_WORKER"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-secret-key-change-me"
os.environ["LOG_LEVEL"] = "CRITICAL"

from fastapi_app.services.notifications import FcmCredentials, FcmNotConfigured

# Shaped like a real service account, with nothing real in it. `private_key`
# is not a usable key: these tests never mint a token, they only decide
# whether the credential is considered present and well-formed.
ACCOUNT = {
    "type": "service_account",
    "project_id": "safeher-test",
    "private_key_id": "0" * 40,
    "private_key": "-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----\n",
    "client_email": "test@safeher-test.iam.gserviceaccount.com",
    "client_id": "1234567890",
}


class TestSources(unittest.TestCase):
    def test_nothing_configured_reports_itself(self):
        credentials = FcmCredentials()

        self.assertFalse(credentials.is_configured)
        with self.assertRaises(FcmNotConfigured):
            credentials.access_token()

    def test_raw_json_in_the_environment_is_accepted(self):
        credentials = FcmCredentials(service_account_json=json.dumps(ACCOUNT))

        self.assertTrue(credentials.is_configured)
        self.assertEqual(credentials.project_id, "safeher-test")

    def test_base64_json_is_accepted(self):
        # Offered because a dashboard that reflows or trims the private key's
        # embedded newlines corrupts it in a way that only shows up later, as
        # an invalid signature from Google.
        encoded = base64.b64encode(json.dumps(ACCOUNT).encode()).decode()
        credentials = FcmCredentials(service_account_json=encoded)

        self.assertTrue(credentials.is_configured)
        self.assertEqual(credentials.project_id, "safeher-test")

    def test_a_file_path_still_works(self):
        # The local development path must not regress: the credential stays
        # gitignored on disk rather than being pasted into a shell.
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "service-account.json"
            path.write_text(json.dumps(ACCOUNT), encoding="utf-8")

            credentials = FcmCredentials(service_account_path=str(path))

            self.assertTrue(credentials.is_configured)
            self.assertEqual(credentials.project_id, "safeher-test")

    def test_the_environment_wins_over_a_path(self):
        # A deployed host must not be silently overridden by a stale path
        # inherited from a developer's .env -- which is exactly the situation
        # that prompted this: FCM_SERVICE_ACCOUNT_FILE pointed at a gitignored
        # file that does not exist on the server.
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "service-account.json"
            path.write_text(json.dumps({**ACCOUNT, "project_id": "from-file"}), encoding="utf-8")

            credentials = FcmCredentials(
                service_account_path=str(path),
                service_account_json=json.dumps({**ACCOUNT, "project_id": "from-env"}),
            )

            self.assertEqual(credentials.project_id, "from-env")


class TestMalformed(unittest.TestCase):
    """Every one of these must read as "push is off", never as a crash.

    An emergency dispatch calls this. A raised exception here would take down
    the alert that reaches the contacts by email, which is the channel that
    actually works.
    """

    def test_a_stale_path_counts_as_unconfigured(self):
        credentials = FcmCredentials(service_account_path="./does-not-exist.json")

        self.assertFalse(credentials.is_configured)

    def test_junk_in_the_variable_does_not_raise(self):
        credentials = FcmCredentials(service_account_json="this is not json")

        self.assertFalse(credentials.is_configured)

    def test_an_empty_variable_falls_through_to_the_path(self):
        # Managed hosts commonly render an unset variable as an empty string
        # rather than omitting it, so empty must mean absent.
        with TemporaryDirectory() as tmp:
            path = Path(tmp) / "service-account.json"
            path.write_text(json.dumps(ACCOUNT), encoding="utf-8")

            credentials = FcmCredentials(service_account_path=str(path), service_account_json="   ")

            self.assertTrue(credentials.is_configured)

    def test_valid_json_missing_the_key_is_not_configured(self):
        # The dangerous case: parses cleanly, so a naive check calls it
        # configured, and the failure moves to token-minting time inside a
        # dispatch.
        without_key = {k: v for k, v in ACCOUNT.items() if k != "private_key"}
        credentials = FcmCredentials(service_account_json=json.dumps(without_key))

        self.assertFalse(credentials.is_configured)

    def test_valid_json_missing_the_client_email_is_not_configured(self):
        without_email = {k: v for k, v in ACCOUNT.items() if k != "client_email"}
        credentials = FcmCredentials(service_account_json=json.dumps(without_email))

        self.assertFalse(credentials.is_configured)

    def test_an_explicit_project_id_does_not_require_a_credential(self):
        # `project_id` is also used to build the endpoint URL, so it must not
        # depend on parsing a credential that may not be there.
        credentials = FcmCredentials(project_id="safeher-explicit")

        self.assertEqual(credentials.project_id, "safeher-explicit")


if __name__ == "__main__":
    unittest.main()
