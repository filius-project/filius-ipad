# Apple Release Readiness

This repository is prepared to prove unsigned compilation and metadata completeness without Apple credentials or hardware. It is **not** configured to sign, upload to TestFlight, or submit to the App Store.

## Current automated evidence

The automated and manual workflows serve different purposes:

- **Project Readiness Contracts** is a fast, cross-platform check on every pull request and push to `main`.
- **Apple Release Readiness (Unsigned Xcode 26)** runs for relevant pushes to `main` and can also be started manually. It verifies that Xcode and the iOS SDK are version 26 or later, builds the Release configuration for a generic iOS device with code signing disabled, and records build identity.
- **Apple Simulator Tests** is manually triggered for release candidates. Its `full` profile divides unit and UI coverage into smaller hosted jobs and uploads separate result bundles and diagnostics.
- **Build Unsigned IPA** is manually triggered after the required test evidence is accepted. It packages and hashes an unsigned IPA but does not repeat the hosted simulator suite.

None of these workflows receives Apple signing credentials or uploads to App Store Connect.

Apple's published submission requirement effective **April 28, 2026** requires iOS and iPadOS apps submitted to App Store Connect to be built with the iOS 26 SDK or later. Passing the readiness workflow demonstrates only unsigned compiler/SDK compatibility with that floor.

## Detailed release plan

- [App Store release preparation plan](app-store-release-plan.md): project-specific findings, ordered work, release gates, TestFlight validation, and submission evidence.

## Repository assets

- [Release checklist](checklist.md)
- [Signing and secret contract](signing-secrets.md)
- [Privacy and export compliance checklist](privacy-export-compliance.md)
- `release/app-store/app-metadata.json`: product-level inventory and unresolved owner decisions.
- `release/app-store/locales/`: localized App Store text placeholders.
- `release/app-store/privacy-questionnaire.json`: privacy decisions that must be reviewed against the shipped binary.
- `release/app-store/export-compliance.json`: encryption/export determination record.
- `release/signing/secret-contract.json`: names and purposes only; never values.
- `release/notes/next.md`: staged release notes.
- `CHANGELOG.md`: durable user-visible change history.

## Validation commands

```text
python scripts/project/validate_project_readiness.py
python -m unittest discover -s scripts/project -p "test_*.py"
```

Repository mode expects explicit `TODO`/`REVIEW_REQUIRED` placeholders and passes when the inventory is structurally complete. Release mode rejects unresolved placeholders:

```text
python scripts/project/validate_project_readiness.py --release
```

The release-mode command is expected to fail until accountable owners replace every placeholder, a signed archive exists, privacy/export answers match that archive, and real-device/TestFlight evidence is linked.

## What remains intentionally impossible

Without Apple account access and approved secrets, the repository cannot prove:

- App ID registration or capability assignment;
- Apple Distribution certificate validity;
- App Store distribution provisioning-profile validity;
- archive signing or App Store validation;
- App Store Connect app-record ownership and metadata acceptance;
- TestFlight upload, processing, beta review, installation, or tester acceptance;
- App Review submission or approval.

Do not reword unsigned success as any of the above.

## Official references

- Apple submission requirements: https://developer.apple.com/news/upcoming-requirements/
- Uploading builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds-overview/
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- Export compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- App Store provisioning profiles: https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile
- App Store Connect API keys: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
- GitHub macOS runner images: https://github.com/actions/runner-images
