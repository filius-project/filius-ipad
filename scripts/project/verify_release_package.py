#!/usr/bin/env python3
"""Validate a compiled FiliusPad app against the release inventory."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path
from typing import Any, Dict, List

EXPECTED_DEVICE_FAMILY = [2]
EXPECTED_DOCUMENT_TYPE = "com.filius.pad.fls"
EXPECTED_EXTENSION = "fls"
EXPECTED_MIME_TYPE = "application/vnd.filius.project"
EXPECTED_ORIENTATIONS = {
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
}


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"cannot read JSON {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain a JSON object")
    return value


def load_plist(path: Path) -> Dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read plist {path}: {error}")
    if not isinstance(value, dict):
        fail(f"{path} must contain a plist dictionary")
    return value


def require_string(mapping: Dict[str, Any], key: str, *, source: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        fail(f"{source}: {key} must be a non-empty string")
    return value


def validate_document_contract(plist: Dict[str, Any]) -> Dict[str, Any]:
    document_types = plist.get("CFBundleDocumentTypes")
    if not isinstance(document_types, list):
        fail("compiled Info.plist: CFBundleDocumentTypes must be an array")
    owns_document = any(
        isinstance(entry, dict)
        and entry.get("CFBundleTypeRole") == "Editor"
        and entry.get("LSHandlerRank") == "Owner"
        and EXPECTED_DOCUMENT_TYPE in entry.get("LSItemContentTypes", [])
        for entry in document_types
    )
    if not owns_document:
        fail("compiled Info.plist: FILIUS document owner declaration is missing")

    exported_types = plist.get("UTExportedTypeDeclarations")
    if not isinstance(exported_types, list):
        fail("compiled Info.plist: UTExportedTypeDeclarations must be an array")
    declaration = next(
        (
            entry
            for entry in exported_types
            if isinstance(entry, dict)
            and entry.get("UTTypeIdentifier") == EXPECTED_DOCUMENT_TYPE
        ),
        None,
    )
    if declaration is None:
        fail("compiled Info.plist: FILIUS exported type declaration is missing")
    tags = declaration.get("UTTypeTagSpecification")
    if not isinstance(tags, dict):
        fail("compiled Info.plist: FILIUS type tags are missing")
    extensions = tags.get("public.filename-extension")
    if isinstance(extensions, str):
        extensions = [extensions]
    if not isinstance(extensions, list) or EXPECTED_EXTENSION not in extensions:
        fail("compiled Info.plist: .fls filename extension is missing")
    if tags.get("public.mime-type") != EXPECTED_MIME_TYPE:
        fail("compiled Info.plist: FILIUS MIME type is incorrect")

    return {
        "typeIdentifier": EXPECTED_DOCUMENT_TYPE,
        "filenameExtension": EXPECTED_EXTENSION,
        "mimeType": EXPECTED_MIME_TYPE,
        "opensInPlace": plist.get("LSSupportsOpeningDocumentsInPlace") is True,
    }


def validate_icons(app: Path, plist: Dict[str, Any]) -> Dict[str, Any]:
    icons = plist.get("CFBundleIcons~ipad")
    if not isinstance(icons, dict):
        fail("compiled Info.plist: CFBundleIcons~ipad is missing")
    primary = icons.get("CFBundlePrimaryIcon")
    if not isinstance(primary, dict):
        fail("compiled Info.plist: iPad primary icon declaration is missing")
    if primary.get("CFBundleIconName") != "AppIcon":
        fail("compiled Info.plist: iPad primary icon name must be AppIcon")
    icon_files = primary.get("CFBundleIconFiles")
    if not isinstance(icon_files, list) or not icon_files or not all(
        isinstance(item, str) and item for item in icon_files
    ):
        fail("compiled Info.plist: iPad primary icon files are missing")

    missing = [
        base
        for base in icon_files
        if not any(candidate.is_file() for candidate in app.glob(f"{base}*.png"))
    ]
    if missing:
        fail(f"compiled app: declared iPad icon files are missing: {', '.join(missing)}")
    if not (app / "Assets.car").is_file():
        fail("compiled app: Assets.car is missing")

    return {
        "iconName": "AppIcon",
        "declaredFiles": icon_files,
        "assetsCatalogPresent": True,
    }


def validate_release_package(app: Path, metadata_path: Path) -> Dict[str, Any]:
    if not app.is_dir():
        fail(f"compiled app bundle does not exist: {app}")
    plist_path = app / "Info.plist"
    plist = load_plist(plist_path)
    metadata = load_json(metadata_path)

    expected_identity = {
        "bundleIdentifier": require_string(metadata, "bundleIdentifier", source=str(metadata_path)),
        "marketingVersion": require_string(metadata, "marketingVersion", source=str(metadata_path)),
        "buildNumber": require_string(metadata, "buildNumber", source=str(metadata_path)),
        "minimumOSVersion": require_string(metadata, "minimumOSVersion", source=str(metadata_path)),
    }
    actual_identity = {
        "bundleIdentifier": require_string(plist, "CFBundleIdentifier", source=str(plist_path)),
        "marketingVersion": require_string(plist, "CFBundleShortVersionString", source=str(plist_path)),
        "buildNumber": require_string(plist, "CFBundleVersion", source=str(plist_path)),
        "minimumOSVersion": require_string(plist, "MinimumOSVersion", source=str(plist_path)),
    }
    for field, expected in expected_identity.items():
        if actual_identity[field] != expected:
            fail(
                f"compiled app {field} {actual_identity[field]!r} does not match "
                f"release inventory {expected!r}"
            )
    if re.fullmatch(r"[0-9]+", actual_identity["buildNumber"]) is None:
        fail("compiled app buildNumber must be numeric")

    device_family = plist.get("UIDeviceFamily")
    if device_family != EXPECTED_DEVICE_FAMILY:
        fail(
            f"compiled Info.plist: UIDeviceFamily must be {EXPECTED_DEVICE_FAMILY}, "
            f"found {device_family!r}"
        )
    if plist.get("LSRequiresIPhoneOS") is not True:
        fail("compiled Info.plist: LSRequiresIPhoneOS must be true")

    platforms = plist.get("CFBundleSupportedPlatforms")
    if not isinstance(platforms, list) or not platforms or not all(
        platform in {"iPhoneOS", "iPhoneSimulator"} for platform in platforms
    ):
        fail(f"compiled Info.plist: unsupported platform declaration {platforms!r}")

    orientations = plist.get("UISupportedInterfaceOrientations~ipad")
    if not isinstance(orientations, list) or set(orientations) != EXPECTED_ORIENTATIONS:
        fail("compiled Info.plist: all four supported iPad orientations must be declared")

    executable_name = require_string(plist, "CFBundleExecutable", source=str(plist_path))
    if not (app / executable_name).is_file():
        fail(f"compiled app executable is missing: {executable_name}")

    return {
        "status": "passed",
        "app": str(app),
        "metadata": str(metadata_path),
        "identity": actual_identity,
        "deviceFamily": device_family,
        "supportedPlatforms": platforms,
        "orientations": sorted(orientations),
        "icons": validate_icons(app, plist),
        "documentContract": validate_document_contract(plist),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument(
        "--metadata",
        type=Path,
        default=Path("release/app-store/app-metadata.json"),
    )
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report = validate_release_package(args.app, args.metadata)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"release package verification failed: {error}", file=sys.stderr)
        return 1

    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
