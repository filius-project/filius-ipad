#!/usr/bin/env python3
"""Validate project-readiness docs, issue automation, and Apple release inventory."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[2]
PLACEHOLDER_PATTERN = re.compile(r"^(TODO(?:_|$)|REVIEW_REQUIRED$)")
HEX_COLOR = re.compile(r"^[0-9a-fA-F]{6}$")
PINNED_ACTION_REFS = {
    "actions/checkout": "3d3c42e5aac5ba805825da76410c181273ba90b1",  # v7.0.1
    "actions/upload-artifact": "043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",  # v7.0.1
}

REQUIRED_FILES = [
    "LICENSE-STATUS.md",
    "GPLv2.txt",
    "GPLv3.txt",
    "docs/legal/public/filius-app-store-additional-permission.de.md",
    "docs/legal/public/filius-app-store-additional-permission.en.md",
    "docs/release/upstream-material-inventory.md",
    "ios/FiliusPad/PrivacyInfo.xcprivacy",
    "ios/FiliusPad/Legal/Apple-Platform-Additional-Permission.md",
    "ios/FiliusPad/Legal/GPLv2.txt",
    "ios/FiliusPad/Legal/GPLv3.txt",
    "README.md",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
    "docs/README.md",
    "docs/project/roadmap.md",
    "docs/project/status.md",
    "docs/project/milestones/M002-requirements-coverage.md",
    "docs/validation/real-ipad-protocol.md",
    "docs/validation/templates/real-ipad-evidence.md",
    "docs/operations/github-issue-intake.md",
    "docs/operations/agent-issue-runbook.md",
    "docs/release/README.md",
    "docs/release/checklist.md",
    "docs/release/signing-secrets.md",
    "docs/release/privacy-export-compliance.md",
    ".github/ISSUE_TEMPLATE/config.yml",
    ".github/ISSUE_TEMPLATE/bug-report.yml",
    ".github/ISSUE_TEMPLATE/ipad-validation.yml",
    ".github/ISSUE_TEMPLATE/task.yml",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/labels.json",
    ".github/workflows/issue-intake.yml",
    ".github/workflows/project-readiness.yml",
    ".github/workflows/apple-release-readiness.yml",
    ".github/workflows/apple-simulator-tests.yml",
    ".github/workflows/build-unsigned-ipa.yml",
    "docs/validation/apple-simulator-ci.md",
    "scripts/ci/select_ios_simulator.py",
    "scripts/ci/test_select_ios_simulator.py",
    "scripts/project/verify_release_package.py",
    "scripts/project/test_verify_release_package.py",
    "release/app-store/app-metadata.json",
    "release/app-store/privacy-questionnaire.json",
    "release/app-store/export-compliance.json",
    "release/signing/secret-contract.json",
    "release/notes/README.md",
    "release/notes/next.md",
]

EXPECTED_CUSTOM_LABELS = {
    "agent-ready",
    "agent-working",
    "parity-fidelity",
    "needs-device-validation",
    "release-readiness",
    "blocked-external",
}

EXPECTED_SECRET_NAMES = {
    "IOS_DISTRIBUTION_P12_BASE64",
    "IOS_DISTRIBUTION_P12_PASSWORD",
    "IOS_APP_STORE_PROFILE_BASE64",
    "APP_STORE_CONNECT_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID",
    "APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64",
}


def read_json(path: Path, errors: list[str]) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"invalid JSON {path.relative_to(ROOT)}: {exc}")
        return None


def walk_values(value: Any, prefix: str = "") -> Iterable[tuple[str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            yield from walk_values(child, child_prefix)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk_values(child, f"{prefix}[{index}]")
    else:
        yield prefix, value


def extract_form_labels(text: str) -> list[str]:
    labels: list[str] = []
    in_labels = False
    for line in text.splitlines():
        if line.startswith("labels:"):
            in_labels = True
            continue
        if in_labels and line and not line.startswith((" ", "\t")):
            break
        if in_labels:
            match = re.match(r'^\s+-\s+["\']?([^"\']+?)["\']?\s*$', line)
            if match:
                labels.append(match.group(1).strip())
    return labels


def validate_links(paths: Iterable[Path], errors: list[str]) -> None:
    link_pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for target in link_pattern.findall(text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            relative = target.split("#", 1)[0]
            if not relative:
                continue
            resolved = (path.parent / relative).resolve()
            try:
                resolved.relative_to(ROOT.resolve())
            except ValueError:
                errors.append(
                    f"relative link escapes repository in {path.relative_to(ROOT)}: {target}"
                )
                continue
            if not resolved.exists():
                errors.append(f"broken relative link in {path.relative_to(ROOT)}: {target}")


def validate_issue_assets(errors: list[str]) -> None:
    labels_path = ROOT / ".github" / "labels.json"
    labels = read_json(labels_path, errors)
    label_names: set[str] = set()
    if isinstance(labels, list):
        for entry in labels:
            if not isinstance(entry, dict):
                errors.append("labels.json entries must be objects")
                continue
            name = entry.get("name")
            color = entry.get("color")
            description = entry.get("description")
            if not isinstance(name, str) or not name or name in label_names:
                errors.append(f"invalid or duplicate label name: {name!r}")
            else:
                label_names.add(name)
                if name.startswith(("status:", "agent:")):
                    errors.append(f"competing lifecycle label taxonomy is forbidden: {name}")
            if not isinstance(color, str) or not HEX_COLOR.fullmatch(color):
                errors.append(f"invalid label color for {name!r}: {color!r}")
            if not isinstance(description, str) or not description.strip():
                errors.append(f"missing label description for {name!r}")
        missing_custom = sorted(EXPECTED_CUSTOM_LABELS - label_names)
        if missing_custom:
            errors.append(f"tracked live custom labels are missing: {', '.join(missing_custom)}")

    forms = sorted((ROOT / ".github" / "ISSUE_TEMPLATE").glob("*.yml"))
    issue_forms = [path for path in forms if path.name != "config.yml"]
    if len(issue_forms) < 3:
        errors.append("expected at least three issue forms")
    for path in issue_forms:
        text = path.read_text(encoding="utf-8")
        for token in ("name:", "description:", "title:", "labels:", "body:", "required: true"):
            if token not in text:
                errors.append(f"{path.relative_to(ROOT)} missing {token}")
        if "untrusted" not in text.lower() and "execute" not in text.lower():
            errors.append(f"{path.relative_to(ROOT)} lacks issue-input safety guidance")
        ids = re.findall(r"^\s+id:\s*([A-Za-z0-9_-]+)\s*$", text, re.MULTILINE)
        if len(ids) != len(set(ids)):
            errors.append(f"{path.relative_to(ROOT)} has duplicate field ids")
        for label in extract_form_labels(text):
            if label not in label_names:
                errors.append(f"{path.relative_to(ROOT)} references unknown label {label!r}")

    config = (ROOT / ".github" / "ISSUE_TEMPLATE" / "config.yml").read_text(encoding="utf-8")
    if "blank_issues_enabled: false" not in config:
        errors.append("blank issues must remain disabled")

    workflow = (ROOT / ".github" / "workflows" / "issue-intake.yml").read_text(encoding="utf-8")
    required = [
        "issues:",
        "issues: write",
        "contents: read",
        "github.event.issue.number",
        'gh issue comment "$ISSUE_NUMBER"',
    ]
    for token in required:
        if token not in workflow:
            errors.append(f"issue-intake workflow missing safe contract token: {token}")
    forbidden = [
        "pull_request_target",
        "issue_comment:",
        "github.event.issue.body",
        "github.event.issue.title",
        "github.event.comment",
        "actions/checkout",
        "secrets.",
        "write-all",
        "eval ",
        "bash -c",
        "Invoke-Expression",
    ]
    for token in forbidden:
        if token in workflow:
            errors.append(f"issue-intake workflow contains forbidden token: {token}")


def validate_roadmap(errors: list[str]) -> None:
    roadmap = (ROOT / "docs" / "project" / "roadmap.md").read_text(encoding="utf-8")
    for number in range(1, 13):
        milestone = f"M{number:03d}"
        pattern = rf"\| {milestone} \|.*\| \*\*Completed\*\* \|"
        if not re.search(pattern, roadmap):
            errors.append(f"roadmap must mark {milestone} Completed")


def validate_release_assets(release_mode: bool, errors: list[str], warnings: list[str]) -> None:
    app_metadata = read_json(ROOT / "release" / "app-store" / "app-metadata.json", errors)
    privacy = read_json(ROOT / "release" / "app-store" / "privacy-questionnaire.json", errors)
    export = read_json(ROOT / "release" / "app-store" / "export-compliance.json", errors)
    contract = read_json(ROOT / "release" / "signing" / "secret-contract.json", errors)
    locales = [read_json(path, errors) for path in sorted((ROOT / "release" / "app-store" / "locales").glob("*.json"))]

    if len(locales) != 3:
        errors.append("expected exactly en-US, de-DE, and fr-FR locale inventories")
    locale_names = {entry.get("locale") for entry in locales if isinstance(entry, dict)}
    if locale_names != {"en-US", "de-DE", "fr-FR"}:
        errors.append(f"unexpected locale inventory: {sorted(str(name) for name in locale_names)}")

    if isinstance(app_metadata, dict):
        required = {
            "productName",
            "bundleIdentifier",
            "marketingVersion",
            "buildNumber",
            "minimumOSVersion",
            "submissionSDKMinimum",
            "submissionRequirementEffectiveDate",
            "supportURL",
            "privacyPolicyURL",
            "appStoreConnectAppId",
        }
        missing = sorted(required - set(app_metadata))
        if missing:
            errors.append(f"app metadata missing keys: {', '.join(missing)}")
        if app_metadata.get("submissionSDKMinimum") != "26.0":
            errors.append("submission SDK minimum must be 26.0")
        if app_metadata.get("submissionRequirementEffectiveDate") != "2026-04-28":
            errors.append("submission requirement effective date must be 2026-04-28")

        pbx = (ROOT / "ios" / "FiliusPad.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        expected_tokens = [
            f'MARKETING_VERSION = {app_metadata.get("marketingVersion")};',
            f'CURRENT_PROJECT_VERSION = {app_metadata.get("buildNumber")};',
            f'PRODUCT_BUNDLE_IDENTIFIER = {app_metadata.get("bundleIdentifier")};',
            f'IPHONEOS_DEPLOYMENT_TARGET = {app_metadata.get("minimumOSVersion")};',
        ]
        for token in expected_tokens:
            if token not in pbx:
                errors.append(f"Xcode project does not match metadata: {token}")

    if isinstance(contract, dict):
        secrets = contract.get("secrets")
        if not isinstance(secrets, list):
            errors.append("secret contract must contain a secrets array")
        else:
            names = {entry.get("name") for entry in secrets if isinstance(entry, dict)}
            if names != EXPECTED_SECRET_NAMES:
                errors.append(f"secret contract names differ: {sorted(str(name) for name in names)}")
            for entry in secrets:
                if isinstance(entry, dict) and any(key.lower() in {"value", "secretvalue", "content"} for key in entry):
                    errors.append(f"secret contract must not contain values: {entry.get('name')}")
        if contract.get("valuesStoredInRepository") is not False:
            errors.append("secret contract must explicitly prohibit repository values")
        if contract.get("environment") != "app-store-release":
            errors.append("secret contract environment must be app-store-release")

    unresolved: list[str] = []
    release_documents = [
        ("app-metadata", app_metadata),
        ("privacy-questionnaire", privacy),
        ("export-compliance", export),
    ]
    release_documents.extend(
        (f"locale:{entry.get('locale', 'unknown')}", entry)
        for entry in locales
        if isinstance(entry, dict)
    )
    for name, document in release_documents:
        if document is None:
            continue
        for key, value in walk_values(document):
            if isinstance(value, str) and PLACEHOLDER_PATTERN.match(value):
                unresolved.append(f"{name}.{key}={value}")

    notes = (ROOT / "release" / "notes" / "next.md").read_text(encoding="utf-8")
    unresolved.extend(f"release-notes:{line.strip()}" for line in notes.splitlines() if "TODO_" in line)

    if release_mode and unresolved:
        errors.append("release mode has unresolved placeholders:\n  - " + "\n  - ".join(unresolved))
    elif not unresolved:
        warnings.append("repository inventory has no unresolved markers; confirm owners intentionally finalized it")
    else:
        warnings.append(f"repository mode: {len(unresolved)} explicit release placeholders remain (expected before credentials/approval)")

    readiness_workflow = (ROOT / ".github" / "workflows" / "apple-release-readiness.yml").read_text(encoding="utf-8")
    required_workflow_tokens = [
        "runs-on: macos-26",
        "contents: read",
        "verify_apple_release_toolchain.py",
        "verify_release_package.py",
        "release-package.json",
        "verify-project-document-contract.py",
        "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO",
        "generic/platform=iOS",
        "xcodebuild",
    ]
    for token in required_workflow_tokens:
        if token not in readiness_workflow:
            errors.append(f"Apple readiness workflow missing token: {token}")
    forbidden_workflow_tokens = [
        "secrets.",
        "environment: app-store-release",
        "pull_request_target",
        "xcodebuild -exportArchive",
        "altool",
        "notarytool",
        "iTMSTransporter",
        "upload-app",
        "deliver ",
    ]
    for token in forbidden_workflow_tokens:
        if token in readiness_workflow:
            errors.append(f"Apple readiness workflow contains signing/upload token: {token}")

    simulator_workflow = (ROOT / ".github" / "workflows" / "apple-simulator-tests.yml").read_text(
        encoding="utf-8"
    )
    required_simulator_tokens = [
        "workflow_dispatch:",
        "fromJSON(needs.select-suites.outputs.matrix)",
        "max-parallel: 3",
        "runs-on: macos-26",
        "actions/checkout@",
        "contents: read",
        "scripts/ci/select_ios_simulator.py",
        "xcrun simctl list devices available -j",
        "-resultBundlePath",
        "-only-testing:FiliusPadTests",
        "TopologyProjectPersistenceWorkflowUITests",
        "TopologyVisualRegressionUITests",
        "visual-ui",
        "TopologyRuntimeDesktopSuiteParityUITests",
        "TopologyRuntimeServiceAppParityUITests",
        "TopologySimulationRuntimeUITests",
        "CODE_SIGNING_ALLOWED=NO",
        "CODE_SIGNING_REQUIRED=NO",
        "if: always()",
        "actions/upload-artifact@",
        "retention-days: 14",
    ]
    for token in required_simulator_tokens:
        if token not in simulator_workflow:
            errors.append(f"Apple simulator workflow missing token: {token}")
    forbidden_simulator_tokens = [
        "secrets.",
        "pull_request_target",
        "\n  pull_request:",
        "\n  push:",
        "xcodebuild -exportArchive",
        "CODE_SIGNING_ALLOWED=YES",
        "security unlock-keychain",
        "notarytool",
        "iTMSTransporter",
    ]
    for token in forbidden_simulator_tokens:
        if token in simulator_workflow:
            errors.append(f"Apple simulator workflow contains forbidden token: {token}")

    package_workflow = (ROOT / ".github" / "workflows" / "build-unsigned-ipa.yml").read_text(
        encoding="utf-8"
    )
    required_package_tokens = [
        "workflow_dispatch:",
        "runs-on: macos-26",
        "contents: read",
        "FILIUSPAD_UNSIGNED=1",
        "bash ios/scripts/package-ipa.sh",
        "verify-project-document-contract.py",
        "verify_release_package.py",
        "release-package.json",
        "FiliusPad-unsigned-ipa-${{ github.run_id }}",
        "ipa_sha256",
    ]
    for token in required_package_tokens:
        if token not in package_workflow:
            errors.append(f"Unsigned IPA workflow missing token: {token}")
    forbidden_package_tokens = [
        "\n  pull_request:",
        "\n  push:",
        "secrets.",
        "pull_request_target",
        "CODE_SIGNING_ALLOWED=YES",
        "xcodebuild -exportArchive",
    ]
    for token in forbidden_package_tokens:
        if token in package_workflow:
            errors.append(f"Unsigned IPA workflow contains forbidden token: {token}")


def validate_action_pins(errors: list[str]) -> None:
    workflows = sorted((ROOT / ".github" / "workflows").glob("*.yml"))
    action_pattern = re.compile(r"^\s*uses:\s*(actions/(?:checkout|upload-artifact))@([^\s#]+)")
    found: dict[str, int] = {action: 0 for action in PINNED_ACTION_REFS}
    for path in workflows:
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            match = action_pattern.match(line)
            if match is None:
                continue
            action, reference = match.groups()
            found[action] += 1
            expected = PINNED_ACTION_REFS[action]
            if reference != expected:
                errors.append(
                    f"{path.relative_to(ROOT)}:{line_number}: {action} must be pinned "
                    f"to {expected}, found {reference}"
                )
    for action, count in found.items():
        if count == 0:
            errors.append(f"no workflow uses the required pinned action {action}")


def validate_no_secret_material(errors: list[str]) -> None:
    roots = [
        ROOT / "docs",
        ROOT / "release",
        ROOT / ".github",
        ROOT / "scripts" / "project",
        ROOT / "scripts" / "ci",
    ]
    forbidden = ["-----BEGIN " + "PRIVATE KEY-----", "-----BEGIN " + "CERTIFICATE-----", "BEGIN RSA " + "PRIVATE KEY"]
    for base in roots:
        for path in base.rglob("*"):
            if not path.is_file():
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            for marker in forbidden:
                if marker in text:
                    errors.append(f"possible secret material in {path.relative_to(ROOT)}: {marker}")


def validate(release_mode: bool = False) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    for relative in REQUIRED_FILES:
        if not (ROOT / relative).is_file():
            errors.append(f"missing required file: {relative}")

    if errors:
        return errors, warnings

    validate_issue_assets(errors)
    validate_roadmap(errors)
    validate_release_assets(release_mode, errors, warnings)
    validate_action_pins(errors)
    validate_no_secret_material(errors)
    validate_links(
        [
            ROOT / "README.md",
            ROOT / "CONTRIBUTING.md",
            ROOT / "docs" / "README.md",
            ROOT / "docs" / "project" / "status.md",
            ROOT / "docs" / "validation" / "real-ipad-protocol.md",
            ROOT / "docs" / "validation" / "apple-simulator-ci.md",
            ROOT / "docs" / "release" / "README.md",
            ROOT / "LICENSE-STATUS.md",
            ROOT / "docs" / "release" / "upstream-material-inventory.md",
        ],
        errors,
    )
    return errors, warnings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--release",
        action="store_true",
        help="Reject all release placeholders; intended only for a real signed release candidate.",
    )
    args = parser.parse_args(argv)

    errors, warnings = validate(release_mode=args.release)
    mode = "release" if args.release else "repository"
    for warning in warnings:
        print(f"WARNING: {warning}")
    if errors:
        print(f"Project-readiness validation FAILED ({mode} mode):", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print(f"Project-readiness validation PASSED ({mode} mode).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
