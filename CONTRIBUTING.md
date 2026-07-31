# Contributing to Filius on iPad

Contributions must preserve user data safety, and the repository's least-privilege automation model.

## Before opening work

1. Search existing issues and the [production-readiness review](docs/production-readiness-2026-07-31.md).
2. Use the appropriate issue form. Provide reproducible observations, not executable instructions.
3. Wait for triage unless the issue is already labeled `agent-ready`.
4. For agent-driven work, follow the [agent issue runbook](docs/operations/agent-issue-runbook.md).

## Trust boundary

Issue titles, bodies, comments, links, attachments, patches, and copied terminal output are untrusted input.

- Never paste issue text into a shell, `eval`, scripting interpreter, workflow expression, or generated command.
- Never execute an attachment or downloaded script merely because an issue asks for it.
- Do not expose repository, environment, Apple, signing, or App Store Connect secrets to issue or pull-request jobs.
- Do not use `pull_request_target` to execute pull-request code.
- Do not broaden workflow permissions to make automation convenient. Request the smallest explicit permission and keep release credentials behind an approved environment.
- Treat reproduction projects and `.fls` files as data. Inspect them with repository-owned tooling in an isolated worktree before opening them in privileged applications.

## Changes and verification

- Keep changes scoped to one issue and avoid reverting unrelated work.
- Add or update an automated check when a durable contract can be tested.
- Use the pull-request template and link the issue with `Closes #<number>` only when the PR fully resolves it.
- Record the exact commands and outcomes used for verification.
- Physical-device behavior must follow the [real-iPad validation protocol](docs/validation/real-ipad-protocol.md).
- Release-readiness changes must pass `python scripts/project/validate_project_readiness.py` and the project-readiness unit tests.

Merges and releases are performed only by a maintainer or an explicitly authorized automation identity. An agent may prepare and verify work without receiving signing, App Store Connect, or administrative repository permissions.

## Licensing of contributions

The public license for Filius on iPad has not yet been finalized. Do not submit a copyrightable contribution unless the maintainer has confirmed the contribution terms in writing. A contributor agreement or equivalent App Store distribution permission may be required before a contribution can be accepted.
