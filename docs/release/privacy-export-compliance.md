# Privacy and Export Compliance Checklist

Answers must describe the exact release binary, bundled SDKs, server behavior, and support practices. Do not infer “no data collected” from product intent alone.

## Privacy inventory

- [ ] Inventory every first- and third-party framework in the archive.
- [ ] Identify all data read from the user, device, files, network, logs, diagnostics, or support channels.
- [ ] For each data category, record collection, purpose, linkage to identity, tracking use, retention, deletion, transmission, and processor.
- [ ] Verify whether simulated network traffic remains on-device or can reach external systems in the release configuration.
- [ ] Review analytics, crash reporting, update checks, web content, email/share flows, document import/export, and support tooling.
- [ ] Confirm child/student/classroom considerations and age-rating answers with the accountable owner.
- [ ] Review system permission usage descriptions and remove unused entitlements/capabilities.
- [ ] Determine whether `PrivacyInfo.xcprivacy` is required for app code or included SDKs; validate declared accessed APIs, reasons, collected data, and tracking against the archive.
- [ ] Publish an approved privacy policy at the final HTTPS URL and ensure App Store metadata points to it.
- [ ] Ensure support documentation explains data deletion/export where applicable.
- [ ] Have the privacy/legal owner approve `release/app-store/privacy-questionnaire.json`.

## Required-reason API and manifest evidence

Keep a release evidence table with API category, calling module/SDK, approved reason, manifest location, and verification owner. A source scan is a prompt for review, not a complete declaration; inspect the archived app and dependency privacy manifests.

## Export compliance

- [ ] Inventory encryption used by app code and dependencies, including only-OS-provided transport, custom cryptography, VPN/tunneling, document protection, and authentication.
- [ ] Determine whether the app uses, contains, or accesses encryption and whether an exemption applies.
- [ ] Record the accountable export-compliance owner and decision rationale in `release/app-store/export-compliance.json`.
- [ ] Obtain any required classification/documentation and record non-secret identifiers/expiry.
- [ ] Ensure App Store Connect answers match the shipped binary and `Info.plist` declaration if used.
- [ ] Re-review after dependency, networking, cryptography, or territory changes.

Repository maintainers and agents may inventory facts but must not make legal attestations unless they are the designated owner.

## Metadata quality and safety

- [ ] App name/subtitle/description/keywords accurately describe shipped behavior.
- [ ] Support and privacy URLs are public, stable, HTTPS, and contain no staging credentials.
- [ ] Screenshots use synthetic content and show the actual release UI.
- [ ] Review notes contain no private account credentials; provide synthetic setup steps.
- [ ] Copyright, content rights, license notices, category, age rating, and availability are approved.
- [ ] Localized metadata is reviewed by a fluent reviewer and stays within App Store Connect limits.

## Release gate

`python scripts/project/validate_project_readiness.py --release` checks structural completeness and unresolved markers. It cannot validate legal accuracy, App Store Connect acceptance, archived dependency manifests, or privacy-policy content. Those require owner review and signed/TestFlight evidence.
