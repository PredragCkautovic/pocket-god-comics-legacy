"""Synthetic-only tests. No commercial assets are included or used."""
from __future__ import annotations
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

from tools.inspect_ipa import archs, inspect

def fake_fat() -> bytes:
    # Minimal headers used for architecture inspection (not executable code).
    return struct.pack(">II", 0xCAFEBABE, 2) + struct.pack(">IIIII", 12, 9, 0, 0, 0) + struct.pack(">IIIII", 12, 11, 0, 0, 0)

class InspectTests(unittest.TestCase):
    def test_fat_armv7_armv7s(self):
        self.assertEqual(archs(fake_fat()), ["armv7", "armv7s"])

    def test_invalid_arch_header(self):
        self.assertEqual(archs(b"nonsense"), ["not-recognized"])

    def test_fake_ipa_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            name = Path(tmp) / "test.ipa"
            root = "Payload/Test.app/"
            info = plistlib.dumps({
                "CFBundleExecutable": "Test",
                "CFBundleIdentifier": "org.example.fake",
                "CFBundleDisplayName": "Synthetic App",
                "MinimumOSVersion": "7.0",
                "UIDeviceFamily": [1, 2],
            })
            manifest = json.dumps({
                "episodes": [{"episode": 1, "pages": ["0001.jpg"]}],
                "art_applied": [],
                "art_missing": [],
            })
            with zipfile.ZipFile(name, "w") as archive:
                archive.writestr(root + "Info.plist", info)
                archive.writestr(root + "Test", fake_fat())
                archive.writestr(root + "PGOfflineLoader.dylib", fake_fat())
                archive.writestr(root + "PGOffline/manifest.json", manifest)
            details = inspect(name)
            self.assertEqual(details["device_families"], [1, 2])
            self.assertEqual(details["minimum_ios_version"], "7.0")
            self.assertEqual(details["offline_episode_count"], 1)
            self.assertEqual(details["offline_page_count"], 1)
            self.assertEqual(details["executable_architectures"], ["armv7", "armv7s"])

    def test_reject_archive_path_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            name = Path(tmp) / "test.ipa"
            with zipfile.ZipFile(name, "w") as archive:
                archive.writestr("../unsafe", b"no")
            with self.assertRaises(ValueError):
                inspect(name)

class CoverTests(unittest.TestCase):
    def test_valid_numbered_covers(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as tmp:
            for n in (26, 27):
                image = Image.new("RGB", (1024, 1536), color=(n, 30, 20))
                image.save(Path(tmp) / f"{n:03d}.png")
            check = subprocess.run([sys.executable, "tools/verify_cover_set.py", tmp,
                                    "--start", "26", "--end", "27", "--strict-size"],
                                   capture_output=True, text=True)
            self.assertEqual(check.returncode, 0, check.stderr)
            self.assertIn("PASS 2 unique numbered covers", check.stdout)

    def test_missing_cover_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            check = subprocess.run([sys.executable, "tools/verify_cover_set.py", tmp,
                                    "--start", "26", "--end", "26"],
                                   capture_output=True, text=True)
            self.assertNotEqual(check.returncode, 0)
