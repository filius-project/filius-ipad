# Production-readiness review — July 31, 2026

## Scope

This review covers the curated `filius-on-ipad` production repository assembled from development revision `3a65cbe`. It evaluates repository hygiene, licensing, build configuration, privacy, security boundaries, release automation, App Store inventory, and verification coverage.

The production repository is intentionally private. This report is not an App Store approval, legal opinion, signed-archive verification, or TestFlight acceptance record.

## Executive assessment

The application has a substantial automated test suite, no third-party package dependencies, bounded `.fls` parsing and archive handling, and least-privilege unsigned CI workflows. The curated repository removes approximately 168 MB of development-only Java runtime and historical parity material.

It is suitable as a private production staging repository. It is **not ready for public source publication, TestFlight external distribution, or App Store submission** until the blocking items below are resolved.

## Release blockers

### P0 — licensing and project identity

1. **Separate license not executed.** The app contains Filius-derived behavior, fixtures, text, and visual assets. A maintainer’s willingness must be converted into a signed license from parties with documented authority over the covered material.
2. **Upstream assets are copied verbatim.** Files under `ios/FiliusPad/TopologyEditor/Assets/JavaParity/` were hash-matched against the upstream Filius resources. The final agreement must cover those assets explicitly.
3. **In-app license statement is provisional.** The Information screen currently states “GNU GPLv2 or GNU GPLv3” and refers to upstream evidence files. It must be changed to the signed separate license before release if the project is not distributed under GPL.
4. **Name and marks require permission.** Permission to use “Filius,” the associated logos, icons, and project identity must be recorded separately or included expressly in the signed agreement.
5. **Repository must remain private.** `LICENSE-STATUS.md` is the authoritative release gate until a final license and public-distribution policy are added.

### P0 — Apple release ownership

1. Confirm that `com.filius.pad` is the intended permanent bundle identifier and can be registered by the correct Apple Developer team. Changing it later affects the App ID, document UTI, preferences, signing, and App Store record.
2. Create and verify the App Store Connect application record, SKU, app identifier, certificates, provisioning profile, and release environment.
3. Complete a signed Release archive, App Store validation, TestFlight processing, installation, and real-iPad acceptance run.

### P1 — App Store inventory

Release-mode validation still intentionally rejects unresolved values, including content-rights approval, copyright wording, SKU, App Store application ID, screenshot requirements, localized descriptions and keywords, review phone number, release notes, export classification, and final approval evidence.

Known public URLs have been populated:

- marketing: `https://filius.app/`
- support: `https://filius.app/support/`
- privacy: `https://filius.app/privacy/`

### P1 — privacy and export review

Static source review found:

- no `URLSession`, Network framework, socket, telemetry, analytics, advertising, or crash-reporting integration;
- no third-party package dependencies;
- one required-reason API category: `UserDefaults`, used for app preferences;
- an isolated non-persistent `WKWebView` with JavaScript disabled and non-`about:` navigation rejected;
- user-created topology projects and simulated credentials stored locally or exported by explicit user action.

`PrivacyInfo.xcprivacy` now declares no tracking, no collected data types, and UserDefaults reason `CA92.1`. The final signed archive must still be inspected before privacy answers are approved.

Export-compliance answers remain unresolved pending review of the final linked binary and Apple’s current questionnaire. No custom cryptographic implementation or third-party crypto package was found in the source tree.

## Repository-hardening changes

- Created a clean production tree without Git history from the development repository.
- Excluded `javaversion/`, `ios/parity/`, `.gsd`, `.env`, generated build output, RTK wrappers, and internal project-planning documents.
- Reduced the working tree from roughly 177 MB to roughly 9 MB before Git metadata.
- Migrated the localization validator and its reviewed allowlists into `scripts/project/`.
- Updated workflows, badges, and private-security-report links to `Borega/filius-on-ipad`.
- Added a privacy manifest to the application target.
- Added `CODEOWNERS`, Dependabot configuration for GitHub Actions, `SECURITY.md`, and an explicit license-status gate.
- Retained only production packaging, document-contract, simulator-selection, repository-readiness, and local test tooling.
- Kept workflows unsigned and without Apple credentials or App Store upload permissions.

## Security observations

### Positive controls

- `.env`, signing material, provisioning profiles, private keys, local Xcode state, and build output are ignored.
- No tracked secret or private-key pattern was identified in the curated tree during static inspection.
- Imported `.fls` archives are treated as untrusted and processed under explicit quotas and path checks.
- Web content is rendered without JavaScript and without external navigation.
- GitHub workflows use explicit minimal permissions and pin critical GitHub-maintained actions by commit SHA.

### Follow-up items

- Run an independent secret scanner against the clean tree before the first push and on every public-release candidate.
- Preserve the rule that no signing credentials are made available to pull-request workflows.
- Add a signed-release workflow only after establishing a protected GitHub environment with required human approval.
- Make clear in user documentation that passwords inside simulated email configurations are simulation data, are stored in project files, and must not be real credentials.
- Continue fuzzing and quota tests for malformed `.fls` archives because imported project files are the primary untrusted-data boundary.

## Verification evidence

Baseline verification on the source development revision:

- macOS 26.5.2
- Xcode 26.6 (`17F113`)
- iOS 26.5 simulator, iPad (A16)
- `./scripts/mac/run-tests.sh --profile unit`
- 392 XCTest tests passed, 0 failures
- result bundle: `/Users/macbookairm2/FiliusTestArtifacts/2026-07-31-095654-3a65cbe-unit/results/unit.xcresult`

Fresh verification of the curated production tree:

- project tooling: 22 project tests and 4 CI tests passed;
- localization: German, English, and French catalogs each contained 844 keys, with no validation errors;
- repository readiness: passed in private/staging mode, with 44 intentional release-owner placeholders still reported;
- GitHub Actions syntax and shell checks: passed with Actionlint 1.7.12;
- secret scan: Gitleaks 8.30.1 scanned the repository and reported no leaks;
- unsigned generic-device Release build: `** BUILD SUCCEEDED **`;
- packaged privacy manifest: present in the built application and validated with `plutil`;
- production unit suite: 392 XCTest tests passed, 0 failures;
- production result bundle: `/Users/macbookairm2/FiliusTestArtifacts/2026-07-31-102551-064b200-unit/results/unit.xcresult`.

The repository-mode checks establish a private production baseline; they do not override the legal, App Store ownership, signed-archive, privacy-approval, and metadata blockers above.

## Publication decision

Keep both repositories private while the license is unresolved. The production repository may be made public only after:

1. the separate license and trademark permission are signed;
2. the final repository license and contribution policy are added;
3. the in-app license text matches the signed agreement;
4. a secret and history review passes; and
5. release-mode validation no longer reports legal or owner-controlled placeholders.
