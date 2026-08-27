#!/usr/bin/env python3
"""Classify the current GitHub Actions change range conservatively.

Only a non-empty range containing exclusively Markdown files is eligible for the
lightweight documentation gate. Every other change, manual dispatch, or
ambiguous range requires the full Apple acceptance build.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ZERO_SHA = "0" * 40


@dataclass(frozen=True)
class ChangeScope:
    candidate_scope: str
    reason: str
    diff_base: str
    head_sha: str
    changed_paths: tuple[str, ...]

    @property
    def docs_only(self) -> bool:
        return self.candidate_scope == "docs-only"


def is_markdown_path(path: str) -> bool:
    return path.lower().endswith(".md")


def classify_paths(paths: Iterable[str]) -> tuple[str, str]:
    normalized = tuple(path.strip().replace("\\", "/") for path in paths if path.strip())
    if not normalized:
        return "full", "empty-or-ambiguous-change-range"
    non_markdown = tuple(path for path in normalized if not is_markdown_path(path))
    if non_markdown:
        return "full", "build-affecting-files-changed"
    return "docs-only", "markdown-only-change-range"


def choose_diff_base(
    *,
    event_name: str,
    event_action: str,
    before_sha: str,
    base_sha: str,
    head_sha: str,
) -> tuple[str, str]:
    if event_name == "workflow_dispatch":
        return "", "manual-dispatch-always-full"
    if event_name == "push":
        if before_sha and before_sha != ZERO_SHA:
            return before_sha, "push-range"
        return f"{head_sha}^", "push-first-parent-fallback"
    if event_name == "pull_request":
        if event_action == "synchronize":
            return f"{head_sha}^", "pull-request-latest-commit-range"
        if base_sha:
            return base_sha, "pull-request-base-range"
        return f"{head_sha}^", "pull-request-first-parent-fallback"
    return "", "unsupported-event-always-full"


def git_changed_paths(base: str, head: str) -> tuple[str, ...]:
    process = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACDMRTUXB", base, head, "--"],
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        raise RuntimeError(process.stderr.strip() or process.stdout.strip() or "git diff failed")
    return tuple(line for line in process.stdout.splitlines() if line.strip())


def classify_change_range(
    *,
    event_name: str,
    event_action: str,
    before_sha: str,
    base_sha: str,
    head_sha: str,
) -> ChangeScope:
    diff_base, range_reason = choose_diff_base(
        event_name=event_name,
        event_action=event_action,
        before_sha=before_sha,
        base_sha=base_sha,
        head_sha=head_sha,
    )
    if not diff_base:
        return ChangeScope("full", range_reason, "", head_sha, ())
    try:
        paths = git_changed_paths(diff_base, head_sha)
    except RuntimeError:
        return ChangeScope("full", f"{range_reason}-unavailable", diff_base, head_sha, ())
    candidate_scope, reason = classify_paths(paths)
    return ChangeScope(candidate_scope, f"{range_reason}:{reason}", diff_base, head_sha, paths)


def validate_docs(scope: ChangeScope) -> None:
    if not scope.docs_only:
        raise RuntimeError(f"change range is not Markdown-only: {scope.reason}")
    for relative in scope.changed_paths:
        path = Path(relative)
        if not path.exists():
            continue
        raw = path.read_bytes()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError as error:
            raise RuntimeError(f"{relative} is not valid UTF-8: {error}") from error
        conflict_lines = [
            number
            for number, line in enumerate(text.splitlines(), start=1)
            if line.startswith(("<<<<<<< ", "=======", ">>>>>>> "))
        ]
        if conflict_lines:
            raise RuntimeError(f"{relative} contains merge-conflict markers at lines {conflict_lines}")


def append_github_output(path: str, values: dict[str, object]) -> None:
    if not path:
        return
    with Path(path).open("a", encoding="utf-8", newline="\n") as handle:
        for key, value in values.items():
            handle.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event-name", required=True)
    parser.add_argument("--event-action", default="")
    parser.add_argument("--before-sha", default="")
    parser.add_argument("--base-sha", default="")
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--github-output", default="")
    parser.add_argument("--report", default="")
    parser.add_argument("--validate-docs", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    scope = classify_change_range(
        event_name=args.event_name,
        event_action=args.event_action,
        before_sha=args.before_sha,
        base_sha=args.base_sha,
        head_sha=args.head_sha,
    )
    if args.validate_docs:
        validate_docs(scope)

    payload = {
        "candidate_scope": scope.candidate_scope,
        "reason": scope.reason,
        "diff_base": scope.diff_base,
        "head_sha": scope.head_sha,
        "changed_paths": list(scope.changed_paths),
    }
    print(json.dumps(payload, indent=2))
    if args.report:
        output = Path(args.report)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    append_github_output(
        args.github_output,
        {
            "candidate_scope": scope.candidate_scope,
            "scope_reason": scope.reason,
            "diff_base": scope.diff_base,
            "head_sha": scope.head_sha,
            "changed_count": len(scope.changed_paths),
        },
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
