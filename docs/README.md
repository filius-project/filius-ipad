# Documentation

This directory is the durable entry point for project status, validation, operations, release preparation, and the executed permission record.

## Project

- [Roadmap](project/roadmap.md): accepted product and parity milestones.
- [Status](project/status.md): current implementation and release readiness.
- [M002 requirements coverage](project/milestones/M002-requirements-coverage.md): durable historical coverage record.
- [M013 experience-quality acceptance](project/milestones/M013-experience-quality-acceptance.md): accepted adaptive UI and interaction work.

## Validation

- [Apple simulator CI](validation/apple-simulator-ci.md): hosted XCTest/XCUITest execution and debugging artifacts.
- [Visual regression baselines](validation/visual-regression.md): canonical screenshots and comparison workflow.
- [Real-iPad protocol](validation/real-ipad-protocol.md): repeatable physical-device acceptance procedure.
- [Evidence template](validation/templates/real-ipad-evidence.md): one copy per device/build/session.

## Operations

- [GitHub issue intake](operations/github-issue-intake.md): labels, state transitions, and trust boundary.
- [Agent issue runbook](operations/agent-issue-runbook.md): claim-to-close procedure and safe GitHub commands.

## Release

- [Release-readiness overview](release/README.md)
- [App Store release preparation plan](release/app-store-release-plan.md)
- [Release checklist](release/checklist.md)
- [Signing and secret contract](release/signing-secrets.md)
- [Privacy and export compliance](release/privacy-export-compliance.md)
- [Upstream material inventory](release/upstream-material-inventory.md): conservative source, resource, fixture, and notice inventory.

## Legal notices

- [Legal publication boundary](legal/README.md)
- [Permission SHA-256 attestation](legal/Filius-Apple-Permission.sha256)
- [License status](../LICENSE-STATUS.md): hash attestation, attribution, and continuing obligations.

The executed permission is retained privately. The signed PDF, paper original, signatures, addresses, and agreement text remain outside Git; only the SHA-256 integrity attestation is published.
