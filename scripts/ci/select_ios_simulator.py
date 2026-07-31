#!/usr/bin/env python3
"""Select a deterministic available iPad simulator from simctl JSON output."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Iterable

PREFERRED_IPAD_NAMES = (
    "iPad (A16)",
    "iPad (10th generation)",
    "iPad Pro 13-inch (M5)",
    "iPad Pro 13-inch (M4)",
    "iPad Air 13-inch (M3)",
    "iPad Air 13-inch (M2)",
)


def runtime_version(identifier: str) -> tuple[int, ...]:
    """Return the numeric iOS runtime version encoded in a simctl identifier."""
    match = re.search(r"\.iOS-(\d+(?:-\d+)*)$", identifier)
    if not match:
        return ()
    return tuple(int(part) for part in match.group(1).split("-"))


def available_ipads(payload: dict[str, Any]) -> Iterable[dict[str, str]]:
    devices_by_runtime = payload.get("devices")
    if not isinstance(devices_by_runtime, dict):
        raise ValueError("simctl payload does not contain a devices object")

    for runtime, devices in devices_by_runtime.items():
        if not isinstance(runtime, str) or ".iOS-" not in runtime:
            continue
        if not isinstance(devices, list):
            continue
        for device in devices:
            if not isinstance(device, dict):
                continue
            name = device.get("name")
            udid = device.get("udid")
            if not isinstance(name, str) or not isinstance(udid, str):
                continue
            if "iPad" not in name:
                continue
            if device.get("isAvailable") is False or device.get("availabilityError"):
                continue
            yield {
                "name": name,
                "udid": udid,
                "runtime": runtime,
                "state": str(device.get("state", "Unknown")),
            }


def select_ipad(payload: dict[str, Any]) -> dict[str, str]:
    candidates = list(available_ipads(payload))
    if not candidates:
        raise ValueError("no available iPad simulator was reported by simctl")

    preference = {name: index for index, name in enumerate(PREFERRED_IPAD_NAMES)}
    candidates.sort(
        key=lambda item: (
            runtime_version(item["runtime"]),
            -preference.get(item["name"], len(preference)),
            item["name"],
        ),
        reverse=True,
    )
    selected = candidates[0]
    selected["destination"] = f"platform=iOS Simulator,id={selected['udid']}"
    return selected


def write_github_output(path: Path, selection: dict[str, str]) -> None:
    with path.open("a", encoding="utf-8", newline="\n") as output:
        for key in ("udid", "name", "runtime", "state", "destination"):
            output.write(f"{key}={selection[key]}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="simctl JSON input file")
    parser.add_argument("--github-output", type=Path, help="optional GitHub Actions output file")
    args = parser.parse_args(argv)

    try:
        payload = json.loads(args.input.read_text(encoding="utf-8"))
        selection = select_ipad(payload)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        parser.error(str(exc))

    if args.github_output:
        write_github_output(args.github_output, selection)
    print(json.dumps(selection, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
