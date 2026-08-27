# Project Status

## Summary

- Product/parity milestones **M001 through M013 are completed** in the tracked repository lineage.
- M013 completes the adaptive experience-quality pass: visual regression, clearer shell controls, two-way software management, shared runtime navigation, context-preserving inspectors, responsive dense views, and bulk editing.
- M012 continues to provide bounded, inert preservation of unknown FILIUS JavaBean/XML content and supplemental `.fls` entries while keeping native edits authoritative.
- Fast project-readiness and localization contracts run on every pull request and push to `main`.
- A hosted Apple simulator workflow is available on demand and splits the complete XCTest/XCUITest release profile into smaller jobs with separate `.xcresult` diagnostics.
- A release-readiness workflow checks clean unsigned Release compilation on relevant pushes to `main` using GitHub `macos-26` with Xcode/iOS SDK 26 or later.
- Unsigned IPA packaging is a manual release action and no longer reruns the historical exact-source parity chain.
- Signed archives, TestFlight upload, and App Store submission are not enabled and are not claimed.
- Physical-device acceptance now has a repeatable protocol and evidence form, but a protocol is not itself a passing device run.
- FiliusPad supports adaptive full-screen, Split View, and Stage Manager sizing alongside other apps, but self-multi-window remains intentionally disabled until each scene has independent editor state, project identity, and autosave ownership.

## Readiness dimensions

| Dimension | State | Evidence / next action |
|---|---|---|
| Milestone parity | Accepted through M013 | [Roadmap](roadmap.md), [M013 acceptance](milestones/M013-experience-quality-acceptance.md), and iOS parity slice records |
| Lossless `.fls` fidelity | Accepted within the bounded safety contract | M012/S01 verifier, two-cycle Swift oracle, Java fixture corpus, and fail-closed XML/reference validation |
| Unsigned IPA | Manual release artifact | Build Unsigned IPA packages, verifies, hashes, and uploads the committed candidate |
| Hosted simulator tests | Manual split matrix | [Apple simulator CI](../validation/apple-simulator-ci.md) runs selected or full XCTest/XCUITest suites and uploads per-suite `.xcresult` evidence |
| Xcode 26 submission-SDK compatibility | Automated unsigned compile gate | Apple Release Readiness workflow; signing/upload remain excluded |
| Real iPad | Protocol ready; run evidence still required per candidate | [Real-iPad protocol](../validation/real-ipad-protocol.md) |
| Issue operations | Ready | [Issue intake](../operations/github-issue-intake.md), templates, labels, and agent runbook |
| App Store metadata | Inventory ready; placeholders unresolved | `release/app-store/` and [release checklist](../release/checklist.md) |
| Signing/App Store credentials | Contract only; unavailable by design | [Signing contract](../release/signing-secrets.md) |
| Privacy/export compliance | Checklist and decision records ready; owner review unresolved | [Privacy/export checklist](../release/privacy-export-compliance.md) |
| TestFlight/App Store | Not runnable | Requires Apple account objects, approved credentials, signed archive, metadata/compliance approval, and release authority |

## Maintainer actions after parity closure

1. Run the physical-device protocol on each release candidate and attach the completed evidence form.
2. File reproducible parity or device findings through the dedicated issue forms and process them through the safe agent intake workflow.
3. Require the fast project-readiness check and Xcode 26 clean-build gate after relevant changes reach `main`.
4. For each release candidate, run and review the manual Apple Simulator Tests `full` matrix before packaging.
5. Run the manual Build Unsigned IPA workflow for the same accepted commit and preserve the artifact with its hash and provenance.
6. Complete signing, App Store metadata, privacy, export-compliance, and release-owner decisions when Apple hardware and credentials are available.

## Release blockers

The following are intentionally unresolved:

- exact source-material mapping and third-party license/attribution review for the release tree (inventory prepared; review still open);
- Apple App ID and capability approval;
- Apple Distribution certificate/private key;
- App Store distribution provisioning profile;
- App Store Connect app record and minimum-role upload credentials;
- final support/privacy URLs, categories, age rating, localized metadata, screenshots, and review contact;
- privacy-manifest/questionnaire and export-compliance owner decisions based on the signed archive;
- signed archive validation, TestFlight processing/install evidence, and App Review approval.

The executed permission removes the former legal-authority blocker for Apple distribution, subject to its continuing conditions. These remaining blockers do not prevent unsigned readiness checks, parity maintenance, or physical-device validation of an installable unsigned candidate. They do prevent any claim that the app is signable, uploaded, submitted, or released through Apple distribution.
