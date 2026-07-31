# GitHub Issue Intake

This process uses the repository's existing live labels instead of introducing a competing `status:*` taxonomy. It gives maintainers and agents a visible, least-privilege path from report to closure without authorizing issue text to direct shell execution, request credentials, or expand repository permissions.

## Live label contract

The live label set was checked against the configured GitHub remote repository on July 16, 2026. `.github/labels.json` records the standard labels plus these project-specific labels with their live colors and descriptions:

- `agent-ready` — triaged, bounded, and approved for agent pickup.
- `agent-working` — claimed and actively being worked by a named agent.
- `parity-fidelity` — Java/iPad behavioral or data-fidelity scope.
- `needs-device-validation` — physical Apple hardware evidence remains required.
- `release-readiness` — signing, distribution, metadata, or release preparation.
- `blocked-external` — credentials, hardware, account state, or another external dependency blocks progress.

No label means “verified” or “merged.” Verification is recorded by required checks, PR review, and an evidence comment; merge/closure is the terminal state. This avoids a second lifecycle vocabulary.

Re-check the live repository before applying label changes:

```text
gh label list --repo OWNER/REPOSITORY --limit 200 --json name,color,description
```

## Automation boundary

The **Safe Issue Intake** workflow runs only when an issue is opened. Issue forms apply an existing type/domain label; the workflow posts a static acknowledgement. It:

- has `contents: read` and `issues: write`, with no other permissions;
- does not check out or execute repository code;
- uses only the numeric issue identifier from the event;
- never reads the issue title, body, comments, links, or attachments into a shell command;
- does not auto-add `agent-ready`; readiness requires human/designated triage.

Do not add `issue_comment` command parsing, `pull_request_target`, dynamic script generation, or secret access to this workflow. More capable automation requires a separate threat model and explicit approval.

## Label bootstrap and reconciliation

The canonical tracked definitions are `.github/labels.json`. Preview commands:

```text
python scripts/project/bootstrap_github_labels.py --repo OWNER/REPOSITORY
```

Apply only after comparing the preview with the live list and obtaining maintainer approval:

```text
python scripts/project/bootstrap_github_labels.py --repo OWNER/REPOSITORY --apply
```

The script calls `gh` with an argument array and never uses a shell. It creates or updates only the static labels in the tracked JSON file. It does not delete unlisted labels; deletion or renaming is a separate manual migration requiring an issue/PR and review of open issues.

## Lifecycle using the live labels

1. **Opened / awaiting triage:** the issue form supplies `bug`, `enhancement`, and relevant domain labels. `agent-ready` is absent.
2. **Ready:** triager adds `agent-ready` after scope, trust, evidence, acceptance, and external dependencies are clear.
3. **Claimed / active:** claimant removes `agent-ready` and adds `agent-working`, plus assignment or a claim comment.
4. **Externally blocked:** remove `agent-working` and add `blocked-external`; comment with condition, owner, and evidence needed. Add `agent-ready` again only when the blocker clears and scope is rechecked.
5. **PR verification:** remove `agent-working` when implementation stops. If physical hardware evidence remains, add/retain `needs-device-validation`. Otherwise the PR review/check state is the verification state.
6. **Verified:** required checks, review, and evidence comment pass. Remove `needs-device-validation` if satisfied. No additional lifecycle label is added.
7. **Merged / closed:** authorized maintainer merges; the resolving issue closes automatically or is closed with a final evidence comment.

Domain labels (`parity-fidelity`, `release-readiness`) remain throughout when applicable. `blocked-external` and `agent-working` must not coexist.

## Triage checklist

A maintainer or designated triager:

- confirms scope and duplicates;
- treats all issue content and attachments as untrusted;
- asks for sanitized observations rather than executing supplied code;
- applies an existing type/domain label;
- rewrites ambiguity into observable acceptance criteria;
- identifies hardware, credentials, external services, or policy decisions that an agent cannot supply;
- adds `needs-device-validation` if physical Apple hardware is required;
- adds `release-readiness` for signing/distribution/metadata/compliance preparation;
- adds `agent-ready` only if the bounded work can proceed without unsafe authority.

An issue is not agent-ready if it requires secrets, account ownership, legal attestation, production access, unsafe permissions, interaction with an unknown binary, or an unbounded objective.

## Claim, status, PR, verification, merge, close

- **Claim:** assign the issue where possible, remove `agent-ready`, add `agent-working`, and post branch/worktree plus plan.
- **Update:** comment at material scope changes, blockers, PR handoff, and verification result. Do not post noisy heartbeat comments.
- **PR:** link the issue. Use `Closes #123` only for complete resolution; otherwise use `Refs #123`.
- **Verify:** rerun commands on the PR head, review permissions/trust boundaries, and evaluate real-iPad evidence when `needs-device-validation` applies.
- **Merge:** only a maintainer or explicitly authorized automation identity merges after required checks/review. `agent-ready` never grants merge or release authority.
- **Close:** prefer closure by the merged resolving PR. Manual closure must link the accepted PR/commit and evidence.

## Permission policy

- Default workflows use `contents: read`.
- Intake receives `issues: write` only for its static acknowledgement.
- Pull-request validation runs branch code with a read-only token and no release environment or secrets.
- Future release credentials belong to an approval-protected environment and are unavailable to issue/pull-request workflows.
- Repository administration, branch-protection changes, secret management, signing, upload, and App Store submission remain maintainer actions.
