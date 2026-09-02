"""Android XML resources must parse, and the ones that carry policy must say so.

## Why this is a test and not a code review

`network_security_config.xml` broke a release build with a comment. XML forbids
`--` inside a comment, an explanatory line used one, and the file sat in the
repository looking fine: `flutter analyze` does not read it, `flutter test` does
not read it, and **debug builds use a different variant of the file entirely**.
The first thing that parsed it was `flutter build apk --release`, four minutes
into a Gradle run.

That is an expensive place to find a typo, and the only place it could be found.
This makes it a one-second check instead.

The second half matters more than the first. The release policy denies cleartext
HTTP everywhere except the glasses' mDNS name, and that exception is what makes
weapon detection work at all in a shipped app. Both halves are easy to lose in
an edit — widening the exception silently weakens every other connection, and
removing it silently disables the camera — so both are asserted.
"""

from __future__ import annotations

import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = PROJECT_ROOT / "mobile" / "android" / "app" / "src"
GLASSES_HOST = "safeher-glasses.local"


def _configs() -> dict[str, Path]:
    return {
        variant: ANDROID_RES / variant / "res" / "xml" / "network_security_config.xml"
        for variant in ("main", "debug", "profile")
    }


class TestAndroidXmlParses(unittest.TestCase):
    def test_every_android_xml_resource_is_well_formed(self):
        files = sorted(ANDROID_RES.rglob("res/**/*.xml"))
        self.assertTrue(files, "no Android XML resources found — has the path moved?")

        broken: list[str] = []
        for path in files:
            try:
                ET.parse(path)
            except ET.ParseError as error:
                broken.append(f"{path.relative_to(PROJECT_ROOT)}: {error}")

        self.assertEqual(
            broken,
            [],
            "malformed Android XML — this fails `flutter build apk --release` "
            "and nothing else",
        )


class TestNetworkSecurityPolicy(unittest.TestCase):
    """The release policy, both halves of it."""

    def setUp(self):
        self.configs = _configs()
        for variant, path in self.configs.items():
            self.assertTrue(path.exists(), f"{variant} config is missing")

    def test_release_denies_cleartext_by_default(self):
        # An attacker on the same cafe wifi must not be able to strip TLS from
        # traffic carrying a woman's location and her recorded evidence.
        root = ET.parse(self.configs["main"]).getroot()
        base = root.find("base-config")

        self.assertIsNotNone(base, "release config has no base-config")
        self.assertEqual(
            base.get("cleartextTrafficPermitted"),
            "false",
            "release builds must deny cleartext HTTP by default",
        )

    def test_the_only_cleartext_exception_is_the_glasses(self):
        # An ESP32-S3 cannot terminate TLS at 15 fps and no CA issues for a
        # device on someone's home wifi, so this one exception is deliberate.
        # Widening it to a whole IP range would re-create the blanket
        # `usesCleartextTraffic` flag that was removed from the manifest.
        root = ET.parse(self.configs["main"]).getroot()
        permitted = [
            domain.text.strip()
            for config in root.findall("domain-config")
            if config.get("cleartextTrafficPermitted") == "true"
            for domain in config.findall("domain")
            if domain.text
        ]

        self.assertEqual(
            permitted,
            [GLASSES_HOST],
            "exactly one host may speak cleartext, and it is the camera",
        )

    def test_the_glasses_exception_exists_at_all(self):
        # Its mirror image: without this entry the camera is unreachable in a
        # release build and weapon detection fails silently, which is how it
        # would ship if someone "tidied up" the exception.
        text = self.configs["main"].read_text(encoding="utf-8")
        self.assertIn(
            GLASSES_HOST,
            text,
            "removing this entry disables weapon detection in release builds",
        )


if __name__ == "__main__":
    unittest.main()
