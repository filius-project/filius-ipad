from __future__ import annotations
import hashlib
import io
import json
import unittest
from unittest import mock
import zipfile

from scripts.ci import github_actions_ipa_status as ci


class RecordingTextStream:
    def __init__(self) -> None:
        self.calls: list[dict[str, str]] = []

    def reconfigure(self, **kwargs: str) -> None:
        self.calls.append(kwargs)


class GitHubActionsIPAStatusTests(unittest.TestCase):
    def test_configure_utf8_text_streams_ignores_incompatible_reconfigure_signature(self) -> None:
        class PositionalOnlyTextStream:
            def reconfigure(self, encoding: str, errors: str, /) -> None:
                raise AssertionError("positional call was not expected")

        ci.configure_utf8_text_streams([PositionalOnlyTextStream()])

    def test_configure_utf8_text_streams_supports_windows_diagnostics(self) -> None:
        stdout = RecordingTextStream()
        stderr = RecordingTextStream()

        ci.configure_utf8_text_streams([stdout, stderr])

        expected = [{"encoding": "utf-8", "errors": "backslashreplace"}]
        self.assertEqual(stdout.calls, expected)
        self.assertEqual(stderr.calls, expected)

    def make_zip(self, files: dict[str, bytes | str]) -> bytes:
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as archive:
            for name, content in files.items():
                archive.writestr(name, content)
        return output.getvalue()

    def test_list_successful_runs_requests_completed_and_filters_conclusion(self) -> None:
        payload = {
            "workflow_runs": [
                {"id": 1, "status": "completed", "conclusion": "success"},
                {"id": 2, "status": "completed", "conclusion": "failure"},
                {"id": 3, "status": "in_progress", "conclusion": None},
            ]
        }
        with mock.patch.object(ci, "github_get_json", return_value=payload) as get_json:
            runs = ci.list_successful_runs("token", ci.RepoRef("owner", "repo"), per_page=500)

        self.assertEqual([run["id"] for run in runs], [1])
        requested_url = get_json.call_args.args[1]
        self.assertIn("status=completed", requested_url)
        self.assertIn("per_page=100", requested_url)

    def test_download_artifact_closes_unexpected_success_response(self) -> None:
        response = mock.MagicMock()
        opener = mock.Mock()
        opener.open.return_value = response
        artifact = ci.ArtifactReport(1, "artifact", 10, False, "later", "https://example.invalid/archive")

        with (
            mock.patch.object(ci.urllib.request, "build_opener", return_value=opener),
            self.assertRaisesRegex(RuntimeError, "did not redirect"),
        ):
            ci.download_artifact_archive("token", artifact)

        response.__enter__.assert_called_once_with()
        response.__exit__.assert_called_once()

    def test_select_workflow_run_returns_latest_matching_run(self) -> None:
        runs = [
            {"name": "Other", "created_at": "2026-07-14T12:00:00Z", "id": 3},
            {"name": "Build Unsigned IPA", "created_at": "2026-07-14T10:00:00Z", "id": 1},
            {"name": "Build Unsigned IPA", "created_at": "2026-07-14T11:00:00Z", "id": 2},
        ]

        selected = ci.select_workflow_run(runs, "Build Unsigned IPA")

        self.assertEqual(selected["id"], 2)

    def test_extract_failed_steps_reports_job_and_step_details(self) -> None:
        jobs = [
            {
                "id": 42,
                "name": "Parity, Swift build, and unsigned IPA",
                "conclusion": "failure",
                "steps": [
                    {"number": 1, "name": "Checkout", "conclusion": "success"},
                    {"number": 5, "name": "Run strict S22 parity chain", "conclusion": "failure"},
                    {"number": 6, "name": "Package", "conclusion": "skipped"},
                ],
            }
        ]

        failures = ci.extract_failed_steps(jobs)

        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0].job_id, 42)
        self.assertEqual(failures[0].step_number, 5)
        self.assertEqual(failures[0].step_name, "Run strict S22 parity chain")

    def test_extract_log_findings_classifies_compiler_tests_archive_and_workflow(self) -> None:
        logs = self.make_zip(
            {
                "job/5_build.txt": "\n".join(
                    [
                        "context before",
                        "/tmp/App.swift:12:7: error: cannot find 'value' in scope",
                        "Test Case '-[FiliusPadTests.RouterTests testRoute]' failed (0.1 seconds).",
                        "** ARCHIVE FAILED **",
                        "** BUILD FAILED **",
                        "[phase:error] Stale parity matrix",
                    ]
                )
            }
        )

        findings, failed_tests = ci.extract_log_findings(logs, max_lines=20, context_lines=1)

        self.assertEqual(
            [finding.category for finding in findings],
            ["swift-compiler", "xctest", "archive-export", "swift-build", "workflow"],
        )
        self.assertEqual(failed_tests, ["FiliusPadTests.RouterTests.testRoute"])
        self.assertIn("context before", findings[0].excerpt)

    def test_extract_ipa_metadata_prefers_metadata_report(self) -> None:
        payload = {
            "ipa_size_bytes": 1234,
            "ipa_sha256": "abc123",
            "sha": "c" * 40,
        }
        archive = self.make_zip({"reports/ipa-metadata.json": json.dumps(payload)})

        size, sha256 = ci.extract_ipa_metadata_from_archive(archive)

        self.assertEqual(size, 1234)
        self.assertEqual(sha256, "abc123")

    def test_extract_ipa_metadata_hashes_single_ipa_when_report_is_absent(self) -> None:
        ipa = b"unsigned-ipa-content"
        archive = self.make_zip({"FiliusPad.ipa": ipa})

        size, sha256 = ci.extract_ipa_metadata_from_archive(archive)

        self.assertEqual(size, len(ipa))
        self.assertEqual(sha256, hashlib.sha256(ipa).hexdigest())

    def test_render_markdown_contains_failure_artifacts_and_hash(self) -> None:
        report = ci.WorkflowReport(
            repo=ci.RepoRef("Borega", "swiftson"),
            workflow="Build Unsigned IPA",
            sha="deadbeef",
            run_id=99,
            run_number=7,
            run_attempt=2,
            event="pull_request",
            status="completed",
            conclusion="failure",
            run_url="https://example.invalid/run/99?label=a|b",
            created_at="2026-07-14T10:00:00Z",
            updated_at="2026-07-14T10:05:00Z",
            failed_steps=[
                ci.FailedStep(42, "build", "failure", 5, "Package IPA", "failure")
            ],
            findings=[
                ci.LogFinding("archive-export", "job/5.txt", 12, "** ARCHIVE FAILED **", ("before", "```", "after"))
            ],
            failed_tests=["FiliusPadTests.RouterTests.testRoute"],
            artifacts=[
                ci.ArtifactReport(1, "FiliusPad-ci-evidence-99", 200, False, "2026-07-28T00:00:00Z")
            ],
            ipa_size_bytes=1234,
            ipa_sha256="abc123",
            validation_scope="full",
        )

        markdown = ci.render_markdown(report)

        self.assertIn("Run ID | `99`", markdown)
        self.assertIn("Validation scope | `full`", markdown)
        self.assertIn("Package IPA", markdown)
        self.assertIn("FiliusPadTests.RouterTests.testRoute", markdown)
        self.assertIn("FiliusPad-ci-evidence-99", markdown)
        self.assertIn("SHA-256: `abc123`", markdown)
        self.assertIn(r"https://example.invalid/run/99?label=a\|b", markdown)
        self.assertIn("    ```", markdown)
        self.assertNotIn("```text", markdown)

    def test_non_markdown_changes_ignores_markdown_paths(self) -> None:
        with (
            mock.patch.object(ci, "ensure_commit_available", return_value=True),
            mock.patch.object(
                ci.subprocess,
                "run",
                return_value=mock.Mock(returncode=0, stdout="README.md\nios/parity/SUMMARY.MD\n", stderr=""),
            ),
        ):
            self.assertEqual(ci.non_markdown_changes_between("a" * 40, "b" * 40), ())

    def test_non_markdown_changes_reports_build_affecting_path(self) -> None:
        with (
            mock.patch.object(ci, "ensure_commit_available", return_value=True),
            mock.patch.object(
                ci.subprocess,
                "run",
                return_value=mock.Mock(returncode=0, stdout="SUMMARY.md\nios/FiliusPad/App.swift\n", stderr=""),
            ),
        ):
            self.assertEqual(
                ci.non_markdown_changes_between("a" * 40, "b" * 40),
                ("ios/FiliusPad/App.swift",),
            )

    def test_find_reusable_ipa_requires_matching_tree_and_live_ipa(self) -> None:
        runs = [
            {"id": 12, "name": "Build Unsigned IPA", "head_sha": "a" * 40, "created_at": "2026-07-15T10:00:00Z"}
        ]
        artifact = ci.ArtifactReport(
            1,
            "FiliusPad-unsigned-ipa-12",
            500,
            False,
            "2026-07-29T00:00:00Z",
            "https://example.invalid/artifact",
        )
        with (
            mock.patch.object(ci, "list_successful_runs", return_value=runs),
            mock.patch.object(ci, "non_markdown_changes_between", return_value=()),
            mock.patch.object(ci, "list_artifacts", return_value=[]),
            mock.patch.object(ci, "artifact_reports", return_value=[artifact]),
            mock.patch.object(
                ci,
                "resolve_ipa_acceptance_metadata",
                return_value={"sha": "c" * 40, "ipa_size_bytes": 1234, "ipa_sha256": "abc123"},
            ),
        ):
            result = ci.find_reusable_ipa_acceptance(
                "token", ci.RepoRef("owner", "repo"), "Build Unsigned IPA", "b" * 40
            )
        self.assertIsNotNone(result)
        self.assertEqual(result.run_id, 12)
        self.assertEqual(result.tree_sha, "c" * 40)
        self.assertEqual(result.ipa_sha256, "abc123")

    def test_extract_docs_only_metadata(self) -> None:
        payload = {
            "validation_scope": "docs-only-reuse",
            "accepted_run_id": 12,
            "accepted_sha": "a" * 40,
            "ipa_size_bytes": 1234,
            "ipa_sha256": "abc123",
        }
        archive = self.make_zip({"reports/docs-only-metadata.json": json.dumps(payload)})
        self.assertEqual(ci.extract_docs_only_metadata_from_archive(archive), payload)

    def test_find_reusable_ipa_rejects_changed_non_markdown_tree(self) -> None:
        runs = [
            {"id": 12, "name": "Build Unsigned IPA", "head_sha": "a" * 40, "created_at": "2026-07-15T10:00:00Z"}
        ]
        with (
            mock.patch.object(ci, "list_successful_runs", return_value=runs),
            mock.patch.object(ci, "non_markdown_changes_between", return_value=("ios/App.swift",)),
            mock.patch.object(ci, "list_artifacts", return_value=[]),
            mock.patch.object(
                ci,
                "artifact_reports",
                return_value=[ci.ArtifactReport(1, "FiliusPad-unsigned-ipa-12", 500, False, "later")],
            ),
            mock.patch.object(
                ci,
                "resolve_ipa_acceptance_metadata",
                return_value={"sha": "c" * 40, "ipa_size_bytes": 1234, "ipa_sha256": "abc123"},
            ),
        ):
            result = ci.find_reusable_ipa_acceptance(
                "token", ci.RepoRef("owner", "repo"), "Build Unsigned IPA", "b" * 40
            )
        self.assertIsNone(result)

    def test_build_report_reads_docs_only_reused_ipa_metadata(self) -> None:
        metadata = {
            "validation_scope": "docs-only-reuse",
            "accepted_run_id": 12,
            "accepted_sha": "a" * 40,
            "ipa_size_bytes": 1234,
            "ipa_sha256": "abc123",
        }
        run = {
            "id": 99,
            "run_number": 8,
            "run_attempt": 1,
            "event": "pull_request",
            "status": "completed",
            "conclusion": "success",
        }
        with (
            mock.patch.object(ci, "list_jobs", return_value=[]),
            mock.patch.object(ci, "list_artifacts", return_value=[]),
            mock.patch.object(ci, "artifact_reports", return_value=[]),
            mock.patch.object(ci, "resolve_ipa_metadata", return_value=(None, None)),
            mock.patch.object(ci, "resolve_docs_only_metadata", return_value=metadata),
        ):
            report = ci.build_report(
                "token", ci.RepoRef("owner", "repo"), "Build Unsigned IPA", "b" * 40, run, 20, False
            )
        self.assertEqual(report.validation_scope, "docs-only-reuse")
        self.assertEqual(report.accepted_run_id, 12)
        self.assertEqual(report.ipa_sha256, "abc123")


if __name__ == "__main__":
    unittest.main()
