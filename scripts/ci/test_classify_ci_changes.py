from __future__ import annotations

import unittest
from unittest import mock

from scripts.ci import classify_ci_changes as scope


class ChangeScopeTests(unittest.TestCase):
    def test_markdown_only_changes_are_lightweight_candidates(self) -> None:
        candidate, reason = scope.classify_paths(["README.md", "ios/parity/m010/s05/SUMMARY.MD"])
        self.assertEqual(candidate, "docs-only")
        self.assertEqual(reason, "markdown-only-change-range")

    def test_any_non_markdown_change_requires_full_build(self) -> None:
        candidate, reason = scope.classify_paths(["SUMMARY.md", ".github/workflows/build.yml"])
        self.assertEqual(candidate, "full")
        self.assertEqual(reason, "build-affecting-files-changed")

    def test_empty_change_range_fails_closed(self) -> None:
        self.assertEqual(
            scope.classify_paths([]),
            ("full", "empty-or-ambiguous-change-range"),
        )

    def test_pull_request_synchronize_uses_latest_commit_range(self) -> None:
        base, reason = scope.choose_diff_base(
            event_name="pull_request",
            event_action="synchronize",
            before_sha="a" * 40,
            base_sha="b" * 40,
            head_sha="c" * 40,
        )
        self.assertEqual(base, f"{'c' * 40}^")
        self.assertEqual(reason, "pull-request-latest-commit-range")

    def test_new_pull_request_uses_complete_base_range(self) -> None:
        base, reason = scope.choose_diff_base(
            event_name="pull_request",
            event_action="opened",
            before_sha="",
            base_sha="b" * 40,
            head_sha="c" * 40,
        )
        self.assertEqual(base, "b" * 40)
        self.assertEqual(reason, "pull-request-base-range")

    def test_manual_dispatch_is_always_full(self) -> None:
        result = scope.classify_change_range(
            event_name="workflow_dispatch",
            event_action="",
            before_sha="",
            base_sha="",
            head_sha="c" * 40,
        )
        self.assertEqual(result.candidate_scope, "full")
        self.assertIn("manual-dispatch", result.reason)

    @mock.patch.object(scope, "git_changed_paths", return_value=("docs/acceptance.md",))
    def test_docs_range_is_reported_with_selected_base(self, changed: mock.Mock) -> None:
        result = scope.classify_change_range(
            event_name="push",
            event_action="",
            before_sha="a" * 40,
            base_sha="",
            head_sha="b" * 40,
        )
        changed.assert_called_once_with("a" * 40, "b" * 40)
        self.assertTrue(result.docs_only)

    @mock.patch.object(scope, "git_changed_paths", side_effect=RuntimeError("missing commit"))
    def test_unavailable_range_fails_closed(self, _: mock.Mock) -> None:
        result = scope.classify_change_range(
            event_name="push",
            event_action="",
            before_sha="a" * 40,
            base_sha="",
            head_sha="b" * 40,
        )
        self.assertEqual(result.candidate_scope, "full")
        self.assertIn("unavailable", result.reason)


if __name__ == "__main__":
    unittest.main()
