from __future__ import annotations

import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from typing import Any, Dict

from scripts.project import verify_release_package as verifier


class ReleasePackageValidationTests(unittest.TestCase):
    def make_package(self) -> tuple[Path, Path, tempfile.TemporaryDirectory[str]]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        app = root / "FiliusPad.app"
        app.mkdir()
        metadata = root / "app-metadata.json"
        metadata.write_text(
            json.dumps(
                {
                    "bundleIdentifier": "com.filius.pad",
                    "marketingVersion": "1.0",
                    "buildNumber": "1",
                    "minimumOSVersion": "17.0",
                }
            ),
            encoding="utf-8",
        )
        plist: Dict[str, Any] = {
            "CFBundleExecutable": "FiliusPad",
            "CFBundleIdentifier": "com.filius.pad",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "MinimumOSVersion": "17.0",
            "UIDeviceFamily": [2],
            "LSRequiresIPhoneOS": True,
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "UISupportedInterfaceOrientations~ipad": sorted(verifier.EXPECTED_ORIENTATIONS),
            "CFBundleIcons~ipad": {
                "CFBundlePrimaryIcon": {
                    "CFBundleIconName": "AppIcon",
                    "CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76"],
                }
            },
            "CFBundleDocumentTypes": [
                {
                    "CFBundleTypeRole": "Editor",
                    "LSHandlerRank": "Owner",
                    "LSItemContentTypes": [verifier.EXPECTED_DOCUMENT_TYPE],
                }
            ],
            "UTExportedTypeDeclarations": [
                {
                    "UTTypeIdentifier": verifier.EXPECTED_DOCUMENT_TYPE,
                    "UTTypeTagSpecification": {
                        "public.filename-extension": [verifier.EXPECTED_EXTENSION],
                        "public.mime-type": verifier.EXPECTED_MIME_TYPE,
                    },
                }
            ],
            "LSSupportsOpeningDocumentsInPlace": True,
        }
        with (app / "Info.plist").open("wb") as handle:
            plistlib.dump(plist, handle)
        for name in (
            "FiliusPad",
            "Assets.car",
            "AppIcon60x60@2x.png",
            "AppIcon76x76@2x~ipad.png",
        ):
            (app / name).write_bytes(b"fixture")
        return app, metadata, temporary

    def mutate_plist(self, app: Path, key: str, value: Any) -> None:
        path = app / "Info.plist"
        with path.open("rb") as handle:
            plist = plistlib.load(handle)
        plist[key] = value
        with path.open("wb") as handle:
            plistlib.dump(plist, handle)

    def test_valid_compiled_package_matches_release_inventory(self) -> None:
        app, metadata, temporary = self.make_package()
        self.addCleanup(temporary.cleanup)

        report = verifier.validate_release_package(app, metadata)

        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["identity"]["bundleIdentifier"], "com.filius.pad")
        self.assertEqual(report["deviceFamily"], [2])
        self.assertTrue(report["icons"]["assetsCatalogPresent"])

    def test_rejects_identity_mismatch(self) -> None:
        app, metadata, temporary = self.make_package()
        self.addCleanup(temporary.cleanup)
        self.mutate_plist(app, "CFBundleIdentifier", "com.example.wrong")

        with self.assertRaisesRegex(ValueError, "does not match release inventory"):
            verifier.validate_release_package(app, metadata)

    def test_rejects_non_numeric_build_number(self) -> None:
        app, metadata, temporary = self.make_package()
        self.addCleanup(temporary.cleanup)
        self.mutate_plist(app, "CFBundleVersion", "rc1")
        inventory = json.loads(metadata.read_text(encoding="utf-8"))
        inventory["buildNumber"] = "rc1"
        metadata.write_text(json.dumps(inventory), encoding="utf-8")

        with self.assertRaisesRegex(ValueError, "must be numeric"):
            verifier.validate_release_package(app, metadata)

    def test_rejects_non_ipad_device_family(self) -> None:
        app, metadata, temporary = self.make_package()
        self.addCleanup(temporary.cleanup)
        self.mutate_plist(app, "UIDeviceFamily", [1, 2])

        with self.assertRaisesRegex(ValueError, "UIDeviceFamily"):
            verifier.validate_release_package(app, metadata)

    def test_rejects_missing_declared_icon_file(self) -> None:
        app, metadata, temporary = self.make_package()
        self.addCleanup(temporary.cleanup)
        (app / "AppIcon76x76@2x~ipad.png").unlink()

        with self.assertRaisesRegex(ValueError, "icon files are missing"):
            verifier.validate_release_package(app, metadata)

    def test_rejects_missing_filius_document_type(self) -> None:
        app, metadata, temporary = self.make_package()
        self.addCleanup(temporary.cleanup)
        self.mutate_plist(app, "CFBundleDocumentTypes", [])

        with self.assertRaisesRegex(ValueError, "document owner declaration"):
            verifier.validate_release_package(app, metadata)


if __name__ == "__main__":
    unittest.main()
