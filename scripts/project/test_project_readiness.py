from __future__ import annotations

import json
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

from scripts.project import bootstrap_github_labels as labels
from scripts.project import validate_project_readiness as readiness
from scripts.project import verify_apple_release_toolchain as toolchain


class ProjectReadinessValidationTests(unittest.TestCase):
    def test_repository_mode_accepts_explicit_future_release_placeholders(self) -> None:
        errors, warnings = readiness.validate(release_mode=False)
        self.assertEqual(errors, [])
        self.assertTrue(any("placeholders remain" in warning for warning in warnings))

    def test_release_mode_fails_closed_until_owners_resolve_placeholders(self) -> None:
        errors, _ = readiness.validate(release_mode=True)
        self.assertTrue(any("unresolved placeholders" in error for error in errors))

    def test_all_issue_template_labels_are_bootstrapped(self) -> None:
        configured = {entry["name"] for entry in labels.load_labels()}
        template_dir = readiness.ROOT / ".github" / "ISSUE_TEMPLATE"
        referenced: set[str] = set()
        for path in template_dir.glob("*.yml"):
            if path.name != "config.yml":
                referenced.update(readiness.extract_form_labels(path.read_text(encoding="utf-8")))
        self.assertTrue(referenced)
        self.assertEqual(referenced - configured, set())

    def test_live_custom_labels_are_canonical_without_status_taxonomy(self) -> None:
        configured = {entry["name"] for entry in labels.load_labels()}
        self.assertTrue(readiness.EXPECTED_CUSTOM_LABELS.issubset(configured))
        self.assertFalse(any(name.startswith(("status:", "agent:")) for name in configured))

    def test_relative_links_cannot_escape_repository(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            docs = root / "docs"
            docs.mkdir()
            outside = root.parent / "outside-readiness-link-target.txt"
            outside.write_text("outside", encoding="utf-8")
            markdown = docs / "README.md"
            markdown.write_text(
                f"[escape](../../{outside.name})\n",
                encoding="utf-8",
            )
            errors: list[str] = []
            with mock.patch.object(readiness, "ROOT", root):
                readiness.validate_links([markdown], errors)
            self.assertEqual(len(errors), 1)
            self.assertIn("escapes repository", errors[0])
            outside.unlink()

    def test_secret_scan_includes_ci_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            helper = root / "scripts" / "ci" / "embedded-key.py"
            helper.parent.mkdir(parents=True)
            helper.write_text("-----BEGIN " + "PRIVATE KEY-----", encoding="utf-8")
            errors: list[str] = []
            with mock.patch.object(readiness, "ROOT", root):
                readiness.validate_no_secret_material(errors)
            self.assertEqual(len(errors), 1)
            self.assertIn("scripts/ci/embedded-key.py", errors[0].replace("\\", "/"))

    def test_intake_workflow_does_not_consume_issue_text(self) -> None:
        workflow = (
            readiness.ROOT / ".github" / "workflows" / "issue-intake.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("github.event.issue.number", workflow)
        for forbidden in (
            "github.event.issue.body",
            "github.event.issue.title",
            "github.event.comment",
            "pull_request_target",
            "actions/checkout",
            "secrets.",
            "eval ",
        ):
            self.assertNotIn(forbidden, workflow)

    def test_apple_simulator_workflow_is_unsigned_and_collects_evidence(self) -> None:
        workflow = (
            readiness.ROOT / ".github" / "workflows" / "apple-simulator-tests.yml"
        ).read_text(encoding="utf-8")
        for required in (
            "workflow_dispatch:",
            "fromJSON(needs.select-suites.outputs.matrix)",
            "max-parallel: 3",
            "runs-on: macos-26",
            "-only-testing:FiliusPadTests",
            "TopologyProjectPersistenceWorkflowUITests",
            "TopologyVisualRegressionUITests",
            "visual-ui",
            "TopologyRuntimeDesktopSuiteParityUITests",
            "TopologyRuntimeServiceAppParityUITests",
            "TopologySimulationRuntimeUITests",
            "-resultBundlePath",
            "actions/upload-artifact@",
            "if: always()",
        ):
            self.assertIn(required, workflow)
        for forbidden in (
            "secrets.",
            "pull_request_target",
            "\n  pull_request:",
            "\n  push:",
            "CODE_SIGNING_ALLOWED=YES",
            "xcodebuild -exportArchive",
        ):
            self.assertNotIn(forbidden, workflow)


    def test_unsigned_ipa_workflow_is_manual_and_unsigned(self) -> None:
        workflow = (
            readiness.ROOT / ".github" / "workflows" / "build-unsigned-ipa.yml"
        ).read_text(encoding="utf-8")
        for required in (
            "workflow_dispatch:",
            "runs-on: macos-26",
            "FILIUSPAD_UNSIGNED=1",
            "bash ios/scripts/package-ipa.sh",
            "verify-project-document-contract.py",
            "FiliusPad-unsigned-ipa-${{ github.run_id }}",
        ):
            self.assertIn(required, workflow)
        for forbidden in (
            "\n  pull_request:",
            "\n  push:",
            "secrets.",
            "CODE_SIGNING_ALLOWED=YES",
            "xcodebuild -exportArchive",
        ):
            self.assertNotIn(forbidden, workflow)


class LabelBootstrapTests(unittest.TestCase):
    def test_label_command_is_an_argument_array_not_a_shell_string(self) -> None:
        label = {"name": "agent-ready", "color": "0E8A16", "description": "Ready"}
        command = labels.label_command("owner/repo", label)
        self.assertIsInstance(command, list)
        self.assertEqual(command[:4], ["gh", "label", "create", "agent-ready"])
        self.assertNotIn("shell=True", labels.render_command(command))

    def test_dry_run_is_default_and_makes_no_gh_call(self) -> None:
        output = StringIO()
        with redirect_stdout(output):
            status = labels.main(["--repo", "owner/repo"])
        self.assertEqual(status, 0)
        self.assertIn("[DRY-RUN]", output.getvalue())
        self.assertIn("No GitHub changes made", output.getvalue())

    def test_invalid_repo_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            labels.label_command("owner/repo;echo unsafe", {"name": "x", "color": "ffffff", "description": "x"})


class AppleToolchainTests(unittest.TestCase):
    def test_xcode_26_and_ios_26_pass(self) -> None:
        report = toolchain.evaluate("26.0", "26.1")
        self.assertEqual(report["status"], "pass")
        self.assertTrue(report["unsignedOnly"])
        self.assertFalse(report["signingAttempted"])
        self.assertFalse(report["uploadAttempted"])

    def test_future_major_versions_also_pass(self) -> None:
        self.assertEqual(toolchain.evaluate("27.0", "27.0")["status"], "pass")

    def test_xcode_or_sdk_below_26_fails(self) -> None:
        self.assertEqual(toolchain.evaluate("25.4", "26.0")["status"], "fail")
        self.assertEqual(toolchain.evaluate("26.0", "25.4")["status"], "fail")

    def test_cli_writes_machine_readable_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "toolchain.json"
            stdout = StringIO()
            with redirect_stdout(stdout):
                status = toolchain.main(
                    [
                        "--xcode-version",
                        "26.2",
                        "--sdk-version",
                        "26.2",
                        "--output",
                        str(output),
                    ]
                )
            self.assertEqual(status, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "pass")
            self.assertIn('"unsignedOnly": true', stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
