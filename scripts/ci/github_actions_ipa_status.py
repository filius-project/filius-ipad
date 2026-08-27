#!/usr/bin/env python3
"""Inspect or await the GitHub Actions unsigned-IPA workflow for a commit.

The helper is the repository's canonical CI inspection surface. It reports failed
jobs/steps, structured log findings, artifact metadata, IPA hashes, and can write
a Markdown report suitable for a pull request or session summary.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


DEFAULT_WORKFLOW = "Build Unsigned IPA"
API_VERSION = "2022-11-28"
USER_AGENT = "filius-ci-helper"
ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TIMESTAMP_PREFIX = re.compile(r"^\ufeff?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s+")


def configure_utf8_text_streams(streams: Iterable[object] | None = None) -> None:
    """Keep structured CI diagnostics printable on Windows legacy consoles."""
    for stream in streams if streams is not None else (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if callable(reconfigure):
            try:
                reconfigure(encoding="utf-8", errors="backslashreplace")
            except (OSError, TypeError, ValueError):
                pass


@dataclass(frozen=True)
class RepoRef:
    owner: str
    repo: str


@dataclass(frozen=True)
class FailedStep:
    job_id: int
    job_name: str
    job_conclusion: str
    step_number: int | None
    step_name: str
    step_conclusion: str


@dataclass(frozen=True)
class LogFinding:
    category: str
    source: str
    line_number: int
    message: str
    excerpt: tuple[str, ...] = ()


@dataclass
class ArtifactReport:
    artifact_id: int
    name: str
    size_bytes: int
    expired: bool
    expires_at: str
    archive_download_url: str = field(repr=False, default="")


@dataclass
class WorkflowReport:
    repo: RepoRef
    workflow: str
    sha: str
    run_id: int
    run_number: int | None
    run_attempt: int | None
    event: str
    status: str
    conclusion: str | None
    run_url: str
    created_at: str
    updated_at: str
    failed_steps: list[FailedStep]
    findings: list[LogFinding]
    failed_tests: list[str]
    artifacts: list[ArtifactReport]
    ipa_size_bytes: int | None = None
    ipa_sha256: str | None = None
    validation_scope: str = "unknown"
    accepted_run_id: int | None = None
    accepted_sha: str | None = None


@dataclass(frozen=True)
class ReusableIPAAcceptance:
    run_id: int
    sha: str
    tree_sha: str
    run_url: str
    ipa_size_bytes: int
    ipa_sha256: str
    artifact_name: str


def run_cmd(args: list[str], input_text: str | None = None) -> str:
    proc = subprocess.run(
        args,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"command failed ({' '.join(args)}): {proc.stderr.strip() or proc.stdout.strip()}")
    return proc.stdout.strip()


def get_token_from_git_credentials() -> str:
    environment_token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if environment_token:
        return environment_token
    out = run_cmd(["git", "credential", "fill"], "protocol=https\nhost=github.com\n\n")
    fields: dict[str, str] = {}
    for line in out.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key.strip()] = value.strip()
    token = fields.get("password", "")
    if not token:
        raise RuntimeError("github credential helper did not return a token/password")
    return token


def infer_repo_from_origin() -> RepoRef:
    origin = run_cmd(["git", "remote", "get-url", "origin"])
    match = re.search(r"github\.com[:/](?P<owner>[^/]+)/(?P<repo>[^/.]+)(?:\.git)?$", origin)
    if not match:
        raise RuntimeError(f"could not parse GitHub owner/repo from origin: {origin}")
    return RepoRef(owner=match.group("owner"), repo=match.group("repo"))


def github_request(token: str, url: str) -> urllib.request.Request:
    return urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": USER_AGENT,
        },
    )


def github_get_bytes(token: str, url: str) -> bytes:
    with urllib.request.urlopen(github_request(token, url), timeout=60) as resp:
        return resp.read()


def github_get_json(token: str, url: str) -> dict:
    return json.loads(github_get_bytes(token, url))


def list_runs(token: str, repo: RepoRef, sha: str) -> list[dict]:
    params = urllib.parse.urlencode({"head_sha": sha, "per_page": 50})
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs?{params}"
    return github_get_json(token, url).get("workflow_runs", [])


def list_successful_runs(token: str, repo: RepoRef, per_page: int = 100) -> list[dict]:
    params = urllib.parse.urlencode({"status": "completed", "per_page": max(1, min(per_page, 100))})
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs?{params}"
    runs = github_get_json(token, url).get("workflow_runs", [])
    return [run for run in runs if run.get("status") == "completed" and run.get("conclusion") == "success"]


def get_run(token: str, repo: RepoRef, run_id: int) -> dict:
    return github_get_json(token, f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}")


def select_workflow_run(runs: Iterable[dict], workflow_name: str) -> dict | None:
    filtered = [run for run in runs if run.get("name") == workflow_name]
    if not filtered:
        return None
    filtered.sort(key=lambda run: run.get("created_at", ""), reverse=True)
    return filtered[0]


def wait_for_completion(token: str, repo: RepoRef, run_id: int, timeout: int, interval: int) -> dict:
    deadline = time.time() + timeout
    while True:
        run = get_run(token, repo, run_id)
        status = run.get("status")
        conclusion = run.get("conclusion")
        print(f"status={status} conclusion={conclusion}")
        if status == "completed":
            return run
        if time.time() >= deadline:
            raise TimeoutError(f"timed out waiting for run {run_id} completion")
        time.sleep(interval)


def list_jobs(token: str, repo: RepoRef, run_id: int) -> list[dict]:
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}/jobs?per_page=100"
    return github_get_json(token, url).get("jobs", [])


def extract_failed_steps(jobs: Iterable[dict]) -> list[FailedStep]:
    failures: list[FailedStep] = []
    for job in jobs:
        job_conclusion = str(job.get("conclusion") or "unknown")
        if job_conclusion in {"success", "skipped"}:
            continue
        job_id = int(job.get("id") or 0)
        job_name = str(job.get("name") or "unnamed job")
        failed_job_steps = [
            step
            for step in job.get("steps", [])
            if step.get("conclusion") not in {"success", "skipped", None}
        ]
        if not failed_job_steps:
            failures.append(
                FailedStep(job_id, job_name, job_conclusion, None, "(job-level failure)", job_conclusion)
            )
            continue
        for step in failed_job_steps:
            failures.append(
                FailedStep(
                    job_id=job_id,
                    job_name=job_name,
                    job_conclusion=job_conclusion,
                    step_number=int(step.get("number")) if step.get("number") is not None else None,
                    step_name=str(step.get("name") or "unnamed step"),
                    step_conclusion=str(step.get("conclusion") or "unknown"),
                )
            )
    return failures


def clean_log_line(line: str) -> str:
    return TIMESTAMP_PREFIX.sub("", ANSI_ESCAPE.sub("", line)).strip()


def classify_log_line(line: str) -> str | None:
    clean = clean_log_line(line)
    if re.search(r"\.swift:\d+:\d+:\s+error:", clean, re.IGNORECASE):
        return "swift-compiler"
    if re.search(r"Test Case ['\"].*test\w+.*['\"] failed", clean, re.IGNORECASE):
        return "xcuitest" if re.search(r"UI Tests?|UITests?", clean, re.IGNORECASE) else "xctest"
    if re.search(r"(?:XCTAssert\w* failed|Testing failed:|Executed \d+ tests?, with \d+ failures?)", clean):
        return "xctest"
    if re.search(r"(?:\*\* (?:ARCHIVE|EXPORT) FAILED \*\*|exportArchive|archive failed|export failed)", clean, re.IGNORECASE):
        return "archive-export"
    if re.search(r"(?:\*\* BUILD FAILED \*\*|Command .* failed with a nonzero exit code)", clean, re.IGNORECASE):
        return "swift-build"
    if re.search(r"(?:\[phase:error\]|\] ✗|Process completed with exit code|##\[error\])", clean):
        return "workflow"
    if re.search(r"\berror:\b", clean, re.IGNORECASE):
        return "error"
    return None


def extract_failed_test_name(line: str) -> str | None:
    clean = clean_log_line(line)
    match = re.search(r"Test Case ['\"]-?\[(?P<suite>[^\s]+) (?P<name>test[^\]]+)\]['\"] failed", clean)
    if match:
        return f"{match.group('suite')}.{match.group('name')}"
    match = re.search(r"Test Case ['\"](?P<name>[^'\"]*test\w+)[\'\"] failed", clean)
    return match.group("name") if match else None


def extract_log_findings(zip_bytes: bytes, max_lines: int, context_lines: int = 2) -> tuple[list[LogFinding], list[str]]:
    findings: list[LogFinding] = []
    failed_tests: list[str] = []
    seen_findings: set[tuple[str, str, int]] = set()
    seen_tests: set[str] = set()

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        for name in sorted(zf.namelist()):
            if name.endswith("/"):
                continue
            text = zf.read(name).decode("utf-8", errors="replace")
            lines = text.splitlines()
            for index, line in enumerate(lines):
                test_name = extract_failed_test_name(line)
                if test_name and test_name not in seen_tests:
                    failed_tests.append(test_name)
                    seen_tests.add(test_name)

                category = classify_log_line(line)
                if not category:
                    continue
                key = (category, name, index + 1)
                if key in seen_findings:
                    continue
                start = max(0, index - context_lines)
                end = min(len(lines), index + context_lines + 1)
                excerpt = tuple(clean_log_line(item) for item in lines[start:end] if clean_log_line(item))
                findings.append(
                    LogFinding(
                        category=category,
                        source=name,
                        line_number=index + 1,
                        message=clean_log_line(line),
                        excerpt=excerpt,
                    )
                )
                seen_findings.add(key)
                if len(findings) >= max_lines:
                    return findings, failed_tests
    return findings, failed_tests


def extract_error_lines_from_logs(zip_bytes: bytes, max_lines: int) -> list[str]:
    """Backward-compatible plain error-line extraction."""
    findings, _ = extract_log_findings(zip_bytes, max_lines=max_lines, context_lines=0)
    return [f"{item.source}:{item.line_number}: {item.message}" for item in findings]


def list_artifacts(token: str, repo: RepoRef, run_id: int) -> list[dict]:
    url = f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}/artifacts?per_page=100"
    return github_get_json(token, url).get("artifacts", [])


def artifact_reports(payloads: Iterable[dict]) -> list[ArtifactReport]:
    reports = [
        ArtifactReport(
            artifact_id=int(item.get("id") or 0),
            name=str(item.get("name") or "unnamed artifact"),
            size_bytes=int(item.get("size_in_bytes") or 0),
            expired=bool(item.get("expired")),
            expires_at=str(item.get("expires_at") or ""),
            archive_download_url=str(item.get("archive_download_url") or ""),
        )
        for item in payloads
    ]
    return sorted(reports, key=lambda item: item.name)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        return None


def download_artifact_archive(token: str, artifact: ArtifactReport) -> bytes:
    request = github_request(token, artifact.archive_download_url)
    try:
        opener = urllib.request.build_opener(_NoRedirect)
        with opener.open(request, timeout=60):
            raise RuntimeError(f"artifact endpoint did not redirect: {artifact.name}")
    except urllib.error.HTTPError as error:
        if error.code not in {301, 302, 303, 307, 308}:
            raise
        location = error.headers.get("Location")
        if not location:
            raise RuntimeError(f"artifact redirect missing Location header: {artifact.name}") from error
    unsigned_request = urllib.request.Request(location, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(unsigned_request, timeout=120) as response:
        return response.read()


def extract_ipa_acceptance_metadata_from_archive(zip_bytes: bytes) -> dict[str, object] | None:
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        metadata_names = [name for name in zf.namelist() if name.endswith("ipa-metadata.json")]
        for name in metadata_names:
            payload = json.loads(zf.read(name).decode("utf-8-sig"))
            size = payload.get("ipa_size_bytes")
            sha256 = payload.get("ipa_sha256")
            tree_sha = payload.get("sha")
            if (
                isinstance(size, int)
                and isinstance(sha256, str)
                and sha256
                and isinstance(tree_sha, str)
                and tree_sha
            ):
                return payload
    return None


def extract_ipa_metadata_from_archive(zip_bytes: bytes) -> tuple[int | None, str | None]:
    metadata = extract_ipa_acceptance_metadata_from_archive(zip_bytes)
    if metadata:
        return int(metadata["ipa_size_bytes"]), str(metadata["ipa_sha256"])
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        ipa_names = [name for name in zf.namelist() if name.lower().endswith(".ipa")]
        if len(ipa_names) == 1:
            ipa = zf.read(ipa_names[0])
            return len(ipa), hashlib.sha256(ipa).hexdigest()
    return None, None


def resolve_ipa_metadata(
    token: str,
    artifacts: list[ArtifactReport],
    skip_download: bool,
) -> tuple[int | None, str | None]:
    if skip_download:
        return None, None
    ordered = sorted(
        artifacts,
        key=lambda item: ("ci-evidence" not in item.name.lower(), "unsigned-ipa" not in item.name.lower()),
    )
    for artifact in ordered:
        if artifact.expired or not artifact.archive_download_url:
            continue
        if "ci-evidence" not in artifact.name.lower() and "unsigned-ipa" not in artifact.name.lower():
            continue
        try:
            size, sha256 = extract_ipa_metadata_from_archive(download_artifact_archive(token, artifact))
        except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile, urllib.error.HTTPError):
            continue
        if size is not None and sha256:
            return size, sha256
    return None, None



def resolve_ipa_acceptance_metadata(
    token: str,
    artifacts: Iterable[ArtifactReport],
) -> dict[str, object] | None:
    for artifact in artifacts:
        if artifact.expired or "ci-evidence" not in artifact.name.lower():
            continue
        try:
            payload = extract_ipa_acceptance_metadata_from_archive(download_artifact_archive(token, artifact))
        except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile, urllib.error.HTTPError):
            continue
        if payload:
            return payload
    return None


def ensure_commit_available(sha: str) -> bool:
    exists = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if exists.returncode == 0:
        return True
    fetch = subprocess.run(
        ["git", "fetch", "--no-tags", "--depth=1", "origin", sha],
        check=False,
        capture_output=True,
        text=True,
    )
    if fetch.returncode != 0:
        return False
    exists = subprocess.run(
        ["git", "cat-file", "-e", f"{sha}^{{commit}}"],
        check=False,
        capture_output=True,
        text=True,
    )
    return exists.returncode == 0


def non_markdown_changes_between(candidate_sha: str, target_sha: str) -> tuple[str, ...] | None:
    if not ensure_commit_available(candidate_sha) or not ensure_commit_available(target_sha):
        return None
    process = subprocess.run(
        ["git", "diff", "--name-only", candidate_sha, target_sha, "--"],
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        return None
    return tuple(
        path for path in process.stdout.splitlines()
        if path.strip() and not path.lower().endswith(".md")
    )


def find_reusable_ipa_acceptance(
    token: str,
    repo: RepoRef,
    workflow_name: str,
    target_sha: str,
    target_tree_sha: str | None = None,
    exclude_run_id: int | None = None,
    max_runs: int = 100,
) -> ReusableIPAAcceptance | None:
    target_tree_sha = target_tree_sha or target_sha
    runs = list_successful_runs(token, repo, per_page=max_runs)
    matching = [
        run for run in runs
        if run.get("name") == workflow_name and int(run.get("id") or 0) != (exclude_run_id or 0)
    ]
    matching.sort(key=lambda run: run.get("created_at", ""), reverse=True)
    for run in matching:
        candidate_sha = str(run.get("head_sha") or "")
        if not candidate_sha:
            continue
        run_id = int(run.get("id") or 0)
        artifacts = artifact_reports(list_artifacts(token, repo, run_id))
        ipa_artifacts = [
            artifact for artifact in artifacts
            if artifact.name.startswith("FiliusPad-unsigned-ipa-")
            and not artifact.expired
            and artifact.size_bytes > 0
        ]
        if not ipa_artifacts:
            continue
        metadata = resolve_ipa_acceptance_metadata(token, artifacts)
        if not metadata:
            continue
        candidate_tree_sha = str(metadata.get("sha") or "")
        if not candidate_tree_sha:
            continue
        changed = non_markdown_changes_between(candidate_tree_sha, target_tree_sha)
        if changed is None or changed:
            continue
        size = metadata.get("ipa_size_bytes")
        sha256 = metadata.get("ipa_sha256")
        if not isinstance(size, int) or not isinstance(sha256, str) or not sha256:
            continue
        return ReusableIPAAcceptance(
            run_id=run_id,
            sha=candidate_sha,
            tree_sha=candidate_tree_sha,
            run_url=str(run.get("html_url") or ""),
            ipa_size_bytes=size,
            ipa_sha256=sha256,
            artifact_name=ipa_artifacts[0].name,
        )
    return None


def reusable_acceptance_payload(
    acceptance: ReusableIPAAcceptance,
    target_sha: str,
    target_tree_sha: str | None = None,
) -> dict[str, object]:
    return {
        "validation_scope": "docs-only-reuse",
        "sha": target_sha,
        "tree_sha": target_tree_sha or target_sha,
        "accepted_run_id": acceptance.run_id,
        "accepted_sha": acceptance.sha,
        "accepted_tree_sha": acceptance.tree_sha,
        "accepted_run_url": acceptance.run_url,
        "ipa_artifact": acceptance.artifact_name,
        "ipa_size_bytes": acceptance.ipa_size_bytes,
        "ipa_sha256": acceptance.ipa_sha256,
    }


def extract_docs_only_metadata_from_archive(zip_bytes: bytes) -> dict[str, object] | None:
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        names = [name for name in zf.namelist() if name.endswith("docs-only-metadata.json")]
        for name in names:
            payload = json.loads(zf.read(name).decode("utf-8-sig"))
            if payload.get("validation_scope") == "docs-only-reuse":
                return payload
    return None


def resolve_docs_only_metadata(token: str, artifacts: Iterable[ArtifactReport]) -> dict[str, object] | None:
    for artifact in artifacts:
        if not artifact.name.startswith("FiliusPad-docs-only-evidence-") or artifact.expired:
            continue
        try:
            payload = extract_docs_only_metadata_from_archive(download_artifact_archive(token, artifact))
        except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile, urllib.error.HTTPError):
            continue
        if payload:
            return payload
    return None

def build_report(
    token: str,
    repo: RepoRef,
    workflow_name: str,
    sha: str,
    run: dict,
    max_error_lines: int,
    skip_artifact_download: bool,
) -> WorkflowReport:
    run_id = int(run["id"])
    jobs = list_jobs(token, repo, run_id)
    failures = extract_failed_steps(jobs)
    findings: list[LogFinding] = []
    failed_tests: list[str] = []
    if run.get("status") == "completed" and run.get("conclusion") != "success":
        try:
            logs = github_get_bytes(
                token,
                f"https://api.github.com/repos/{repo.owner}/{repo.repo}/actions/runs/{run_id}/logs",
            )
            findings, failed_tests = extract_log_findings(logs, max_lines=max_error_lines)
        except urllib.error.HTTPError as error:
            findings.append(
                LogFinding("workflow", "run-logs", 0, f"failed to download logs: HTTP {error.code}")
            )

    artifacts = artifact_reports(list_artifacts(token, repo, run_id))
    ipa_size, ipa_sha256 = resolve_ipa_metadata(token, artifacts, skip_download=skip_artifact_download)
    docs_metadata = None if ipa_sha256 or skip_artifact_download else resolve_docs_only_metadata(token, artifacts)
    validation_scope = "full" if ipa_sha256 else "unknown"
    accepted_run_id = None
    accepted_sha = None
    if docs_metadata:
        validation_scope = "docs-only-reuse"
        ipa_size = docs_metadata.get("ipa_size_bytes") if isinstance(docs_metadata.get("ipa_size_bytes"), int) else None
        ipa_sha256 = str(docs_metadata.get("ipa_sha256") or "") or None
        accepted_run_id = int(docs_metadata.get("accepted_run_id") or 0) or None
        accepted_sha = str(docs_metadata.get("accepted_sha") or "") or None
    return WorkflowReport(
        repo=repo,
        workflow=workflow_name,
        sha=sha,
        run_id=run_id,
        run_number=int(run["run_number"]) if run.get("run_number") is not None else None,
        run_attempt=int(run["run_attempt"]) if run.get("run_attempt") is not None else None,
        event=str(run.get("event") or ""),
        status=str(run.get("status") or "unknown"),
        conclusion=run.get("conclusion"),
        run_url=str(run.get("html_url") or ""),
        created_at=str(run.get("created_at") or ""),
        updated_at=str(run.get("updated_at") or ""),
        failed_steps=failures,
        findings=findings,
        failed_tests=failed_tests,
        artifacts=artifacts,
        ipa_size_bytes=ipa_size,
        ipa_sha256=ipa_sha256,
        validation_scope=validation_scope,
        accepted_run_id=accepted_run_id,
        accepted_sha=accepted_sha,
    )


def print_report(report: WorkflowReport) -> None:
    print(
        f"workflow='{report.workflow}' run_id={report.run_id} run_number={report.run_number} "
        f"attempt={report.run_attempt} event={report.event} sha={report.sha}"
    )
    if report.run_url:
        print(f"run_url={report.run_url}")
    print(f"final_status={report.status} final_conclusion={report.conclusion}")
    print(f"validation_scope={report.validation_scope}")
    if report.accepted_run_id:
        print(f"accepted_run_id={report.accepted_run_id}")
    if report.accepted_sha:
        print(f"accepted_sha={report.accepted_sha}")

    if report.failed_steps:
        print("failed_steps:")
        for failure in report.failed_steps:
            step = f" step={failure.step_number}" if failure.step_number is not None else ""
            print(
                f"- job_id={failure.job_id} job='{failure.job_name}'{step} "
                f"name='{failure.step_name}' conclusion={failure.step_conclusion}"
            )

    if report.failed_tests:
        print("failed_tests:")
        for name in report.failed_tests:
            print(f"- {name}")

    if report.findings:
        print("log_findings:")
        for finding in report.findings:
            print(f"- [{finding.category}] {finding.source}:{finding.line_number}: {finding.message}")
    elif report.conclusion not in {None, "success"}:
        print("log_findings: (none matched)")

    if report.artifacts:
        print("artifacts:")
        for artifact in report.artifacts:
            print(
                f"- {artifact.name} id={artifact.artifact_id} size_bytes={artifact.size_bytes} "
                f"expired={artifact.expired} expires_at={artifact.expires_at}"
            )
    if report.ipa_size_bytes is not None:
        print(f"ipa_size_bytes={report.ipa_size_bytes}")
    if report.ipa_sha256:
        print(f"ipa_sha256={report.ipa_sha256}")


def markdown_escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(report: WorkflowReport) -> str:
    icon = "✅" if report.conclusion == "success" else "❌" if report.status == "completed" else "⏳"
    lines = [
        f"## {icon} {report.workflow}",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Run ID | `{report.run_id}` |",
        f"| Run number / attempt | `{report.run_number}` / `{report.run_attempt}` |",
        f"| Commit | `{report.sha}` |",
        f"| Event | `{markdown_escape(report.event)}` |",
        f"| Status | `{markdown_escape(report.status)}` |",
        f"| Conclusion | `{markdown_escape(report.conclusion)}` |",
        f"| Validation scope | `{markdown_escape(report.validation_scope)}` |",
    ]
    if report.accepted_run_id:
        lines.append(f"| Reused full-build run | `{report.accepted_run_id}` |")
    if report.accepted_sha:
        lines.append(f"| Reused full-build commit | `{report.accepted_sha}` |")
    if report.run_url:
        lines.append(f"| Run | {markdown_escape(report.run_url)} |")

    if report.failed_steps:
        lines.extend(["", "### Failed jobs and steps", "", "| Job | Step | Conclusion |", "| --- | --- | --- |"])
        for failure in report.failed_steps:
            step_name = failure.step_name
            if failure.step_number is not None:
                step_name = f"{failure.step_number}. {step_name}"
            lines.append(
                f"| {markdown_escape(failure.job_name)} | {markdown_escape(step_name)} | "
                f"`{markdown_escape(failure.step_conclusion)}` |"
            )

    if report.failed_tests:
        lines.extend(["", "### Failed XCTest/XCUITest cases", ""])
        lines.extend(f"- `{markdown_escape(name)}`" for name in report.failed_tests)

    if report.findings:
        lines.extend(["", "### Relevant log findings", ""])
        for finding in report.findings:
            lines.append(
                f"- **{markdown_escape(finding.category)}** — "
                f"`{markdown_escape(finding.source)}:{finding.line_number}`: {markdown_escape(finding.message)}"
            )
            if finding.excerpt:
                lines.append("")
                lines.extend(f"    {line}" for line in finding.excerpt)

    lines.extend(["", "### Artifacts", ""])
    if report.artifacts:
        lines.extend(["| Name | Size (bytes) | Expired | Expires at |", "| --- | ---: | --- | --- |"])
        for artifact in report.artifacts:
            lines.append(
                f"| `{markdown_escape(artifact.name)}` | {artifact.size_bytes} | "
                f"{str(artifact.expired).lower()} | `{markdown_escape(artifact.expires_at)}` |"
            )
    else:
        lines.append("No artifacts were reported.")

    if report.ipa_size_bytes is not None or report.ipa_sha256:
        lines.extend(["", "### IPA", ""])
        if report.ipa_size_bytes is not None:
            lines.append(f"- Size: `{report.ipa_size_bytes}` bytes")
        if report.ipa_sha256:
            lines.append(f"- SHA-256: `{report.ipa_sha256}`")
    return "\n".join(lines).rstrip() + "\n"


def write_markdown_report(path: str, report: WorkflowReport) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_markdown(report), encoding="utf-8")
    print(f"markdown_report={output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check/wait GitHub IPA workflow status and produce structured evidence.")
    parser.add_argument("--repo", help="owner/repo (default: infer from origin)")
    parser.add_argument("--sha", help="commit SHA (default: HEAD)")
    parser.add_argument("--run-id", type=int, help="inspect a specific workflow run instead of selecting by SHA")
    parser.add_argument("--workflow", default=DEFAULT_WORKFLOW, help=f"workflow name (default: {DEFAULT_WORKFLOW})")
    parser.add_argument("--wait", action="store_true", help="wait until run completes")
    parser.add_argument("--timeout", type=int, default=1800, help="max wait seconds when --wait is set")
    parser.add_argument("--interval", type=int, default=15, help="poll interval seconds when --wait is set")
    parser.add_argument("--max-error-lines", type=int, default=80, help="maximum structured log findings")
    parser.add_argument("--markdown-output", help="write a Markdown report to this path")
    parser.add_argument(
        "--find-reusable-ipa",
        action="store_true",
        help="find a prior successful IPA run whose non-Markdown tree matches --sha",
    )
    parser.add_argument("--exclude-run-id", type=int, help="run ID to exclude from reusable IPA lookup")
    parser.add_argument("--tree-sha", help="exact checked-out tree commit; PR workflows should pass github.sha")
    parser.add_argument("--reuse-metadata-output", help="write reusable IPA metadata JSON to this path")
    parser.add_argument("--github-output", help="append reusable IPA fields to a GitHub Actions output file")
    parser.add_argument(
        "--skip-artifact-download",
        action="store_true",
        help="report artifact metadata without downloading evidence/IPA content for the hash",
    )
    return parser.parse_args()


def main() -> int:
    configure_utf8_text_streams()
    args = parse_args()
    try:
        token = get_token_from_git_credentials()
        if args.repo:
            if "/" not in args.repo:
                raise RuntimeError("--repo must be in owner/repo format")
            owner, repo_name = args.repo.split("/", 1)
            repo = RepoRef(owner=owner, repo=repo_name)
        else:
            repo = infer_repo_from_origin()

        sha = args.sha or run_cmd(["git", "rev-parse", "HEAD"])
        if args.find_reusable_ipa:
            acceptance = find_reusable_ipa_acceptance(
                token=token,
                repo=repo,
                workflow_name=args.workflow,
                target_sha=sha,
                target_tree_sha=args.tree_sha,
                exclude_run_id=args.exclude_run_id,
            )
            if not acceptance:
                print(f"No reusable successful IPA acceptance found for non-Markdown tree at {sha}")
                return 4
            payload = reusable_acceptance_payload(acceptance, sha, args.tree_sha)
            print(json.dumps(payload, indent=2))
            if args.reuse_metadata_output:
                output = Path(args.reuse_metadata_output)
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
                print(f"reuse_metadata={output}")
            if args.github_output:
                with Path(args.github_output).open("a", encoding="utf-8", newline="\n") as handle:
                    for key, value in payload.items():
                        handle.write(f"{key}={value}\n")
            return 0
        if args.run_id:
            run = get_run(token, repo, args.run_id)
            if run.get("name") != args.workflow:
                raise RuntimeError(
                    f"run {args.run_id} is workflow {run.get('name')!r}, expected {args.workflow!r}"
                )
            sha = str(run.get("head_sha") or sha)
        else:
            run = select_workflow_run(list_runs(token, repo, sha), args.workflow)
            if not run:
                print(f"No workflow run named '{args.workflow}' found for sha {sha}")
                return 2

        run_id = int(run["id"])
        print(f"run_id={run_id} sha={sha} workflow='{args.workflow}'")
        if run.get("html_url"):
            print(f"run_url={run.get('html_url')}")
        if args.wait:
            run = wait_for_completion(token, repo, run_id, args.timeout, args.interval)

        report = build_report(
            token=token,
            repo=repo,
            workflow_name=args.workflow,
            sha=sha,
            run=run,
            max_error_lines=args.max_error_lines,
            skip_artifact_download=args.skip_artifact_download,
        )
        print_report(report)
        if args.markdown_output:
            write_markdown_report(args.markdown_output, report)

        if report.status != "completed":
            return 3
        return 0 if report.conclusion == "success" else 1
    except Exception as exc:
        print(f"fatal: {exc}")
        return 10


if __name__ == "__main__":
    raise SystemExit(main())
