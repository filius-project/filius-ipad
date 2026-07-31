#!/usr/bin/env python3
"""Create/update the repository's static GitHub labels without invoking a shell."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LABELS = ROOT / ".github" / "labels.json"
REPO_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
COLOR_PATTERN = re.compile(r"^[0-9a-fA-F]{6}$")


def load_labels(path: Path = DEFAULT_LABELS) -> list[dict[str, str]]:
    labels = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(labels, list) or not labels:
        raise ValueError("label file must contain a non-empty JSON array")

    seen: set[str] = set()
    for index, label in enumerate(labels):
        if not isinstance(label, dict):
            raise ValueError(f"label {index} must be an object")
        if set(label) != {"name", "color", "description"}:
            raise ValueError(f"label {index} must contain only name, color, description")
        name = label["name"]
        if not isinstance(name, str) or not name.strip() or name in seen:
            raise ValueError(f"label {index} has an empty or duplicate name")
        if not COLOR_PATTERN.fullmatch(label["color"]):
            raise ValueError(f"label {name!r} has an invalid six-digit color")
        if not isinstance(label["description"], str) or not label["description"].strip():
            raise ValueError(f"label {name!r} has no description")
        seen.add(name)
    return labels


def label_command(repo: str, label: dict[str, str]) -> list[str]:
    if not REPO_PATTERN.fullmatch(repo):
        raise ValueError("--repo must be OWNER/REPOSITORY using GitHub-safe characters")
    return [
        "gh",
        "label",
        "create",
        label["name"],
        "--repo",
        repo,
        "--color",
        label["color"],
        "--description",
        label["description"],
        "--force",
    ]


def render_command(command: Iterable[str]) -> str:
    """Render only for operator preview; execution still receives an argument array."""
    return subprocess.list2cmdline(list(command))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="GitHub repository as OWNER/REPOSITORY")
    parser.add_argument("--labels", type=Path, default=DEFAULT_LABELS)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply label changes. Without this flag the command is a dry-run preview.",
    )
    args = parser.parse_args(argv)

    try:
        labels = load_labels(args.labels)
        commands = [label_command(args.repo, label) for label in labels]
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"label bootstrap error: {exc}", file=sys.stderr)
        return 2

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"[{mode}] {len(commands)} labels for {args.repo}")
    for command in commands:
        print(render_command(command))

    if not args.apply:
        print("No GitHub changes made. Re-run with --apply after maintainer approval.")
        return 0

    if shutil.which("gh") is None:
        print("label bootstrap error: gh CLI is not installed", file=sys.stderr)
        return 3

    for command in commands:
        completed = subprocess.run(command, check=False)
        if completed.returncode != 0:
            print(
                f"label bootstrap error: gh exited {completed.returncode} while applying {command[3]!r}",
                file=sys.stderr,
            )
            return completed.returncode

    print("Label bootstrap complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
