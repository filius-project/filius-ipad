#!/usr/bin/env python3
"""Verify the FILIUS project import and document-type contracts."""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any

TYPE_IDENTIFIER = "com.filius.pad.fls"
ZIP_TYPE_IDENTIFIER = "public.zip-archive"
FILENAME_EXTENSION = "fls"


def fail(message: str) -> None:
    raise ValueError(message)


def as_string_list(value: Any, *, field: str) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return value
    fail(f"{field} must be a string or an array of strings")


def load_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read plist {path}: {error}")
    if not isinstance(value, dict):
        fail(f"plist root must be a dictionary: {path}")
    return value


def validate_document_plist(path: Path) -> dict[str, Any]:
    plist = load_plist(path)

    declarations = plist.get("UTExportedTypeDeclarations")
    if not isinstance(declarations, list):
        fail(f"{path}: UTExportedTypeDeclarations must be an array")
    matching_declarations = [
        declaration
        for declaration in declarations
        if isinstance(declaration, dict)
        and declaration.get("UTTypeIdentifier") == TYPE_IDENTIFIER
    ]
    if len(matching_declarations) != 1:
        fail(
            f"{path}: expected exactly one exported declaration for "
            f"{TYPE_IDENTIFIER}, found {len(matching_declarations)}"
        )

    declaration = matching_declarations[0]
    conforms_to = as_string_list(
        declaration.get("UTTypeConformsTo"),
        field=f"{path}: UTTypeConformsTo",
    )
    if ZIP_TYPE_IDENTIFIER not in conforms_to:
        fail(f"{path}: {TYPE_IDENTIFIER} must conform to {ZIP_TYPE_IDENTIFIER}")

    tags = declaration.get("UTTypeTagSpecification")
    if not isinstance(tags, dict):
        fail(f"{path}: UTTypeTagSpecification must be a dictionary")
    extensions = as_string_list(
        tags.get("public.filename-extension"),
        field=f"{path}: public.filename-extension",
    )
    if extensions != [FILENAME_EXTENSION]:
        fail(
            f"{path}: exported filename extensions must be exactly "
            f"[{FILENAME_EXTENSION!r}], found {extensions!r}"
        )

    document_types = plist.get("CFBundleDocumentTypes")
    if not isinstance(document_types, list) or not document_types:
        fail(f"{path}: CFBundleDocumentTypes must be a non-empty array")

    claimed_content_types: list[str] = []
    claimed_extensions: list[str] = []
    matching_document_types = 0
    for index, document_type in enumerate(document_types):
        if not isinstance(document_type, dict):
            fail(f"{path}: CFBundleDocumentTypes[{index}] must be a dictionary")
        content_types = as_string_list(
            document_type.get("LSItemContentTypes"),
            field=f"{path}: CFBundleDocumentTypes[{index}].LSItemContentTypes",
        )
        claimed_content_types.extend(content_types)
        if TYPE_IDENTIFIER in content_types:
            matching_document_types += 1
            if document_type.get("CFBundleTypeRole") != "Editor":
                fail(f"{path}: the FILIUS document role must be Editor")
        if "CFBundleTypeExtensions" in document_type:
            claimed_extensions.extend(
                as_string_list(
                    document_type["CFBundleTypeExtensions"],
                    field=(
                        f"{path}: CFBundleDocumentTypes[{index}]"
                        ".CFBundleTypeExtensions"
                    ),
                )
            )

    if matching_document_types != 1:
        fail(
            f"{path}: expected exactly one document type claiming {TYPE_IDENTIFIER}, "
            f"found {matching_document_types}"
        )
    if ZIP_TYPE_IDENTIFIER in claimed_content_types:
        fail(f"{path}: CFBundleDocumentTypes must not claim the broad zip type")
    if "zip" in {extension.lower().lstrip(".") for extension in claimed_extensions}:
        fail(f"{path}: CFBundleDocumentTypes must not claim the .zip extension")

    return {
        "path": str(path),
        "type_identifier": TYPE_IDENTIFIER,
        "conforms_to": conforms_to,
        "filename_extensions": extensions,
        "document_content_types": claimed_content_types,
    }


def validate_swift_source(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    required = [
        "FiliusProjectImportResourcePolicy.accepts(",
        "isRegularFile: resourceValues.isRegularFile",
        "isRegularFile == true",
        f'exportedAs: "{TYPE_IDENTIFIER}"',
        "conformingTo: .zip",
    ]
    for token in required:
        if token not in text:
            fail(f"{path}: missing Swift contract token {token!r}")

    forbidden = [
        'UTType(filenameExtension: "fls")',
        "?? .zip",
        "resourceValues.isRegularFile != false",
    ]
    for token in forbidden:
        if token in text:
            fail(f"{path}: forbidden fail-open/dynamic type token remains: {token!r}")

    return {
        "path": str(path),
        "regular_file_policy": "isRegularFile == true",
        "uttype_initializer": "exportedAs",
    }


def validate_xctest_source(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    required = [
        "(true, true)",
        "(false, false)",
        "(nil, false)",
        f'XCTAssertEqual(UTType.filiusProjectArchive.identifier, "{TYPE_IDENTIFIER}")',
        "XCTAssertTrue(UTType.filiusProjectArchive.conforms(to: .zip))",
    ]
    for token in required:
        if token not in text:
            fail(f"{path}: missing regression-test token {token!r}")
    return {"path": str(path), "regular_file_cases": ["true", "false", "nil"]}


def validate_project(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")

    section_pattern = re.compile(
        r"/\* Begin .*? section \*/(?P<body>.*?)/\* End .*? section \*/",
        re.DOTALL,
    )
    definition_pattern = re.compile(
        r"^(?:\t\t| {8})([A-F0-9]{24})(?: /\*.*?\*/)? = \{",
        re.MULTILINE,
    )
    definitions = [
        identifier
        for section in section_pattern.finditer(text)
        for identifier in definition_pattern.findall(section.group("body"))
    ]
    duplicate_ids = sorted(
        identifier for identifier, count in Counter(definitions).items() if count > 1
    )
    if duplicate_ids:
        fail(f"{path}: duplicate PBX object definitions: {', '.join(duplicate_ids)}")

    configuration_pattern = re.compile(
        r"^\s*[A-F0-9]{24} /\* (Debug|Release) \*/ = \{\n"
        r".*?buildSettings = \{(?P<settings>.*?)^\s*\};\n"
        r"\s*name = \1;\n\s*\};",
        re.MULTILINE | re.DOTALL,
    )
    app_configurations: dict[str, str] = {}
    for match in configuration_pattern.finditer(text):
        settings = match.group("settings")
        if "PRODUCT_BUNDLE_IDENTIFIER = com.filius.pad;" in settings:
            app_configurations[match.group(1)] = settings

    if set(app_configurations) != {"Debug", "Release"}:
        fail(
            f"{path}: expected Debug and Release app configurations, found "
            f"{sorted(app_configurations)}"
        )
    for name, settings in app_configurations.items():
        if "GENERATE_INFOPLIST_FILE = NO;" not in settings:
            fail(f"{path}: {name} app configuration must disable generated Info.plist")
        if "INFOPLIST_FILE = FiliusPad/Info.plist;" not in settings:
            fail(f"{path}: {name} app configuration must use FiliusPad/Info.plist")

    required_tokens = [
        "/* Info.plist */ = {isa = PBXFileReference;",
        "/* FiliusProjectDocumentTypeTests.swift */ = {isa = PBXFileReference;",
        "/* FiliusProjectDocumentTypeTests.swift in Sources */ = {isa = PBXBuildFile;",
    ]
    for token in required_tokens:
        if token not in text:
            fail(f"{path}: missing project wiring token {token!r}")

    return {
        "path": str(path),
        "pbx_object_definition_count": len(definitions),
        "duplicate_pbx_ids": duplicate_ids,
        "app_configurations": sorted(app_configurations),
    }


def validate_workflow(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    required = [
        'unzip -p "$ipa" "Payload/FiliusPad.app/Info.plist"',
        "verify-project-document-contract.py",
        '--packaged-plist "$packaged_plist"',
        "project-document-contract.json",
    ]
    for token in required:
        if token not in text:
            fail(f"{path}: missing packaged Info.plist verification token {token!r}")
    return {"path": str(path), "packaged_info_plist_check": True}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-plist", type=Path, default=Path("ios/FiliusPad/Info.plist"))
    parser.add_argument(
        "--project",
        type=Path,
        default=Path("ios/FiliusPad.xcodeproj/project.pbxproj"),
    )
    parser.add_argument(
        "--swift-source",
        type=Path,
        default=Path("ios/FiliusPad/TopologyEditor/View/TopologyEditorView.swift"),
    )
    parser.add_argument(
        "--test-source",
        type=Path,
        default=Path("ios/FiliusPadTests/FiliusProjectDocumentTypeTests.swift"),
    )
    parser.add_argument(
        "--workflow",
        type=Path,
        default=Path(".github/workflows/build-unsigned-ipa.yml"),
    )
    parser.add_argument("--packaged-plist", type=Path)
    parser.add_argument("--report", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report: dict[str, Any] = {
            "status": "passed",
            "source_plist": validate_document_plist(args.source_plist),
            "swift_source": validate_swift_source(args.swift_source),
            "xctest_source": validate_xctest_source(args.test_source),
            "xcode_project": validate_project(args.project),
            "workflow": validate_workflow(args.workflow),
        }
        if args.packaged_plist is not None:
            report["packaged_plist"] = validate_document_plist(args.packaged_plist)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"project document contract verification failed: {error}", file=sys.stderr)
        return 1

    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
