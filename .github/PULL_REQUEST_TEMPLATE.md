## Linked issue

Closes #

## Scope

- What changed:
- Explicitly not changed:

## Safety and trust boundary

- [ ] No issue/comment/attachment text is executed as code or shell input.
- [ ] No new secret, signing asset, credential, personal data, or unsafe permission is committed.
- [ ] Workflow permissions are explicit and least privilege.
- [ ] This PR does not use `pull_request_target` to execute pull-request code.

## Verification

| Check | Command/protocol | Result/evidence |
|---|---|---|
| Repository validation | `python scripts/project/validate_project_readiness.py` | |
| Automated tests | | |
| Real-iPad case(s), if applicable | | |
| Apple Xcode 26 unsigned readiness, if applicable | Apple Release Readiness workflow | |

## Reviewer notes

- Risk and rollback:
- Follow-up issues:
