#!/usr/bin/env python3
"""Verify the Apple compiler/SDK submission floor without using signing credentials."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

VERSION_PATTERN = re.compile(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[^0-9].*)?$")
MINIMUM_MAJOR = 26


def parse_version(value: str) -> tuple[int, int, int]:
    match = VERSION_PATTERN.fullmatch(value.strip())
    if not match:
        raise ValueError(f"unrecognized version: {value!r}")
    return tuple(int(part or 0) for part in match.groups())  # type: ignore[return-value]


def evaluate(xcode_version: str, sdk_version: str) -> dict[str, object]:
    xcode = parse_version(xcode_version)
    sdk = parse_version(sdk_version)
    errors: list[str] = []
    if xcode[0] < MINIMUM_MAJOR:
        errors.append(f"Xcode {xcode_version} is below required major version {MINIMUM_MAJOR}")
    if sdk[0] < MINIMUM_MAJOR:
        errors.append(f"iOS SDK {sdk_version} is below required major version {MINIMUM_MAJOR}")
    return {
        "requirementEffectiveDate": "2026-04-28",
        "minimumXcodeMajor": MINIMUM_MAJOR,
        "minimumIOSSDKMajor": MINIMUM_MAJOR,
        "xcodeVersion": xcode_version,
        "iosSDKVersion": sdk_version,
        "unsignedOnly": True,
        "signingAttempted": False,
        "uploadAttempted": False,
        "status": "pass" if not errors else "fail",
        "errors": errors,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xcode-version", required=True)
    parser.add_argument("--sdk-version", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    try:
        report = evaluate(args.xcode_version, args.sdk_version)
    except ValueError as exc:
        print(f"toolchain verification error: {exc}", file=sys.stderr)
        return 2

    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    print(payload, end="")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
