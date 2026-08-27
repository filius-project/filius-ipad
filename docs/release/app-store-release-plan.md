# App Store Release Preparation Plan

- **Status:** Legal permission executed; App Store preparation required
- **Target platform:** iPadOS 17.0 and later
- **Document date:** July 18, 2026
**Audience:** FiliusPad maintainers, release owners, Apple Developer account owners, and CI maintainers

## Purpose

This document turns the current App Store release findings into an executable release plan. A reader who has not followed the preceding development work should be able to use it to move FiliusPad from unsigned CI builds to a signed TestFlight candidate and, finally, an App Store submission.

This is a release runbook, not a claim that the app is ready for submission. The current repository proves unsigned Release compilation and automated simulator/test coverage. It does not yet prove distribution signing, App Store Connect upload, TestFlight installation, or App Review acceptance.

## Executive summary

The Apple-platform permission gate is now resolved. The remaining highest-priority work is:

1. Create and approve the Apple Developer and App Store Connect records.
2. Add and approve the production iPad store assets.
3. Configure a protected signed Release archive path without weakening the existing unsigned CI evidence workflow.
4. Complete privacy and export-compliance decisions against the actual shipped binary.
5. Validate one signed build on physical iPads through TestFlight.
6. Submit complete, accurate metadata and the exact tested build for review.

Do not begin another resource-intensive end-to-end UI test round until the cheap release gates pass. A 90-minute UI run cannot detect a missing App Store icon, an invalid signing identity, an absent App Store record, or an invalid IPA export. Those checks should happen first.

## Current repository findings

### Build and identity

The current iPad application is configured with these values:

| Setting | Current value | Release implication |
|---|---|---|
| Bundle identifier | `com.filius.pad` | Must be registered as the final App ID and App Store Connect bundle ID |
| Marketing version | `1.0` | Suitable as a first release if approved by the product owner |
| Build number | `1` | Every later uploaded build must use a new numeric build number |
| Minimum OS | iPadOS 17.0 | Confirm this support floor against the device/tester plan |
| Device family | iPad only | Store screenshots and testing must cover iPad; confirm this is intentional |
| Swift language version | Swift 5 | Not itself an App Store blocker; keep the current toolchain warning-free |
| Document type | `.fls`, UTI `com.filius.pad.fls` | Compiled-package validation is automated; Files-app and TestFlight behavior still require device evidence |

The current project has code signing disabled and has no configured development team. The existing release-readiness workflow intentionally builds an unsigned app for a generic iOS device. That workflow should remain as a credential-free verification job; it is not a distribution workflow.

### Resolved legal input

The returned scan of the executed agreement shows both parties’ handwritten signatures. Sören Schröder signed in Hamburg on August 19, 2026; Dr. Stefan Freischlad signed in Haiger on August 23, 2026. Under the agreement, the latest signing date controls, so the additional permission is effective **August 23, 2026**. The scan is retained in the private production tree only; its SHA-256 is `9827ca00c24c861644e10f0b6c39aa5deeb7cf8966f79f69070fcb7868ad9d75`. The public repository must contain only the clean permission copy and the app must expose that copy with the GPL texts.

This resolves the previously missing effective Apple-distribution permission. It does not replace the separate source-material inventory, third-party license review, Apple account setup, privacy/export decisions, signing, device, or App Review gates.

### Missing or unresolved release inputs

The following items were not present or were not proven during the repository audit:

- Product-owner approval of the existing production-sized app icon on Home Screen, Settings, and TestFlight
- Apple Developer Team ID
- Registered App ID and App Store Connect app record
- Apple Distribution certificate and provisioning profile, or approved automatic-signing setup
- Signed archive and exported IPA
- TestFlight processing/install evidence
- `PrivacyInfo.xcprivacy`, or a documented decision that no manifest is required after API audit
- App Store privacy questionnaire answers
- Export-compliance determination
- Final support URL and privacy-policy URL
- Final app name, subtitle, description, keywords, category, age rating, screenshots, and review notes
- Approved release owner for privacy, export, and App Review attestations

The project-readiness validator currently passes in repository mode while reporting unresolved release placeholders. That is expected before Apple credentials and owner decisions are supplied. Release mode must remain a final gate and should not be changed merely to make placeholders disappear.

## Release phases

## Phase 0 — Freeze the release candidate

**Goal:** Establish exactly what is being released before signing or submission work begins.

- [ ] Confirm the product name: FiliusPad or another final store name.
- [ ] Confirm that iPad-only distribution is intentional.
- [ ] Confirm the minimum supported iPadOS version.
- [ ] Confirm the first marketing version, for example `1.0` or `1.0.0`.
- [ ] Define the build-number policy. Use a monotonically increasing number, preferably derived from CI or the release tag.
- [ ] Freeze the release branch or tag candidate.
- [ ] Confirm that no debug-only screens, fixtures, test data, diagnostics, or development endpoints are exposed in Release.
- [ ] Record the commit SHA used for all release artifacts.
- [ ] Ensure the changelog and release notes describe only user-visible shipped behavior.

**Exit gate:** The team can name the exact bundle ID, version, build number, commit, supported device family, and supported OS range.

## Phase 1 — Create the Apple account-side objects

**Goal:** Make the app identifiable and signable by Apple.

An authorized account owner must complete these actions in Apple Developer and App Store Connect:

- [ ] Accept all current Apple Developer and App Store Connect agreements.
- [ ] Register the explicit App ID for `com.filius.pad`.
- [ ] Enable only capabilities that the app actually uses.
- [ ] Create the App Store Connect app record using the approved name, bundle ID, SKU, primary language, and platform.
- [ ] Confirm the account roles needed by the release owner and CI uploader.
- [ ] Create an Apple Distribution certificate, or approve automatic signing as the release model.
- [ ] Create an App Store distribution provisioning profile if manual signing is used.
- [ ] Create an App Store Connect API key with the minimum role needed for upload and build management.
- [ ] Assign a named owner for certificate, profile, and API-key rotation.
- [ ] Create a protected CI environment for distribution releases. Pull-request and issue-triggered jobs must not access it.

Apple requires an App Store Connect app record before a build can be uploaded. The uploaded build must match the record through the bundle identifier and version/build settings.

**Exit gate:** The owner can open the App Store Connect app record, and a maintainer can identify the approved signing model without exposing credentials to the repository.

## Phase 2 — Complete the application package

**Goal:** Make the binary and store assets suitable for customers and review.

### App icon

The repository contains an `AppIcon` catalog with a 1024 × 1024 marketing image and the iPad target references it. The compiled-package validator now verifies the catalog output and declared iPad icon files. Product approval and device/TestFlight presentation remain outstanding.

- [x] Add the app icon catalog and target configuration.
- [x] Verify that compiled Release products contain the asset catalog and declared iPad icon files.
- [ ] Confirm that the 1024 × 1024 artwork is the approved production design.
- [ ] Check the icon on the Home Screen, in Settings, and in TestFlight.
- [ ] Verify that no placeholder icon remains in the signed archive.

### File handling

The application declares support for `.fls` files. Test the complete system integration rather than only the in-app parser:

- [ ] Open a valid `.fls` file from the Files app.
- [ ] Import a valid `.fls` from a share/open-in action.
- [ ] Reject malformed or unsupported files without crashing.
- [ ] Save changes and reopen the file.
- [ ] Export/share a project from the application.
- [ ] Test duplicate names, cancellation, interrupted transfers, and read-only locations.
- [ ] Confirm that the declared document type and exported UTI match the actual file format.

### Release configuration

Keep Debug and test configurations usable for development, but give distribution its own controlled configuration.

The signed Release path must:

- [ ] Enable code signing.
- [ ] Set the approved Team ID.
- [ ] Use the final bundle identifier.
- [ ] Use the intended Release entitlements only.
- [ ] Embed the app icon and required resources.
- [ ] Embed the privacy manifest if the audit requires one.
- [ ] Produce a numeric build number.
- [ ] Avoid test-only launch arguments and environment variables.
- [ ] Avoid logging sensitive user data.
- [ ] Avoid development certificates and ad-hoc export settings.

## Phase 3 — Privacy, security, and export decisions

**Goal:** Ensure the disclosures and compliance answers match the binary that will be submitted.

### Privacy audit

Audit the application source, build settings, and all dependencies for:

- Data sent to a server
- Analytics or crash-reporting SDKs
- Advertising or tracking
- Account identifiers
- Contact, file, photo, location, or device data
- UserDefaults and local persistence
- File timestamps, disk-space APIs, or other required-reason APIs
- Third-party frameworks with their own privacy manifests

Then:

- [x] Add `PrivacyInfo.xcprivacy` for the reviewed `UserDefaults` required-reason API; revalidate it in the final archive.
- [ ] Declare only API reasons that are actually applicable.
- [ ] Complete App Store Connect App Privacy details.
- [ ] Publish a stable HTTPS privacy-policy URL.
- [ ] Ensure the policy describes local storage, sharing, diagnostics, and deletion behavior accurately.
- [ ] Recheck the answers against the final archive, not only the source tree.

Apple’s privacy-manifest and App Privacy requirements apply to the shipped app and included SDKs. A source-only assumption is not sufficient for the final release decision.

### Export compliance

The app appears to be an educational network simulator and no custom cryptographic framework usage was found in the audited application sources. This is an observation, not a legal determination.

- [ ] Review all dependencies and future networking additions.
- [ ] Determine whether the app uses only exempt operating-system encryption or any non-exempt encryption.
- [ ] Complete App Store Connect export-compliance questions.
- [ ] Add the appropriate `ITSAppUsesNonExemptEncryption` value only after the technical/legal determination.
- [ ] Preserve the determination and its owner in the release evidence.

### Security and data handling

- [ ] Confirm no signing credentials, API keys, or private URLs are packaged in the app.
- [ ] Confirm release logs do not expose project contents or personal data.
- [ ] Confirm imported projects are handled safely and malformed XML/archive content cannot crash the app.
- [ ] Confirm external document names and content are not inserted into unsafe UI or diagnostic output.
- [ ] Review third-party notices, licenses, and attribution, including the Java runtime components, using the [upstream material inventory](upstream-material-inventory.md).
- [x] Archive the Apple-platform additional permission executed in two identical paper originals hand-signed by both parties; retain Sören’s original and a private archival scan. Evidence: `LICENSE-STATUS.md` and the private scan archive.
- [ ] Confirm the release tree against the [upstream material inventory](upstream-material-inventory.md), including the listed stable-version provenance and third-party notices.

## Phase 4 — Store metadata and review materials

**Goal:** Give App Review and customers enough accurate information to understand and use the app.

Prepare and approve:

- [ ] App name
- [ ] Subtitle
- [ ] Full description
- [ ] Keywords
- [ ] Primary and secondary categories
- [ ] Age rating
- [ ] Copyright
- [ ] Content-rights declaration
- [ ] Support URL
- [ ] Privacy-policy URL
- [ ] Optional marketing URL
- [ ] Availability and price
- [ ] iPad screenshots for every required display class
- [ ] Optional app preview video
- [ ] Review contact information
- [ ] Review notes and a short synthetic demo scenario
- [ ] First-release notes

The review notes should explain that FiliusPad is an iPad network-topology editor and simulator. They should provide a short path through the main experience, for example:

1. Launch the app.
2. Create a new topology.
3. Add hosts, switches, or routers.
4. Connect the devices.
5. Open the configuration or simulation controls.
6. Start the simulation.
7. Save, import, or export a project using `.fls` files.

If no login, paid feature, subscription, or external service is required, state that explicitly. If any of those are added later, update the review instructions and compliance work before submission.

## Phase 5 — Cheap automated release gates

**Goal:** Catch deterministic packaging problems before spending hours on UI tests.

Add or run a release validator that checks:

- [x] Compiled bundle ID matches the release inventory.
- [x] Compiled marketing version matches the release inventory.
- [x] Build number is numeric and matches the release inventory; upload uniqueness remains an owner check.
- [x] Compiled minimum OS and iPad-only device family match the release inventory.
- [x] Compiled app icon assets exist and are referenced by the target.
- [x] Compiled document type and UTI declarations are present.
- [ ] Privacy manifest decision is represented.
- [ ] Export-compliance decision is represented.
- [ ] No unresolved release placeholders remain.
- [ ] No debug-only flags or test bundles are embedded in the app.
- [ ] Release archive can be created.
- [ ] Archive signature verifies.
- [ ] IPA export succeeds.
- [ ] IPA contains the expected Info.plist values.
- [ ] IPA contains the expected icon and resources.
- [ ] The archive can be validated by Apple tooling.

The existing unsigned Release workflow should remain a separate, credential-free check. A signed distribution workflow must be protected and manually authorized.

**Exit gate:** One signed archive and IPA pass all deterministic checks without requiring a full UI test suite.

## Phase 6 — Physical-device and TestFlight validation

**Goal:** Validate the exact distribution artifact that customers will install.

Test the signed Release build on physical iPads, preferably through TestFlight:

### Installation and lifecycle

- [ ] Fresh installation.
- [ ] Update over the previous build.
- [ ] Launch after device restart.
- [ ] Background and foreground transitions.
- [ ] Low-storage behavior.
- [ ] Offline behavior.
- [ ] Uninstall and reinstall behavior.

### Core functionality

- [ ] Create and edit a topology.
- [ ] Add, remove, and configure supported devices.
- [ ] Connect and reconnect topology elements.
- [ ] Run and stop the network simulation.
- [ ] Exercise validation and error states.
- [ ] Save and restore projects.
- [ ] Import and export `.fls` files.
- [ ] Use the Files app and Share Sheet integration.
- [ ] Test a large topology for memory and responsiveness.

### UI and accessibility

- [ ] Portrait and landscape layouts.
- [ ] Light and dark mode.
- [ ] Dynamic Type where supported.
- [ ] VoiceOver labels and focus order.
- [ ] Keyboard and pointer interactions where supported.
- [ ] Touch targets and gesture conflicts.
- [ ] No clipped controls or inaccessible sheets.
- [ ] Localized English, German, and French flows.

### Evidence

Record:

- Device model and iPadOS version
- TestFlight build number
- Commit SHA
- Test date
- Tester
- Pass/fail result for each critical case
- Crash logs and reproduction steps
- Screenshots or screen recordings for any failure

Do not rerun the entire expensive suite after every small metadata change. Separate the test layers:

| Change type | Required verification |
|---|---|
| Store text or screenshots only | Metadata review; no binary UI run required |
| Build setting, signing, Info.plist, resources | Archive/package validation and focused smoke test |
| Core Swift/UI behavior | Relevant unit/UI tests and focused physical-device test |
| Release-candidate commit | Full agreed acceptance suite once, after all cheaper gates pass |

## Phase 7 — Upload, submit, and release

**Goal:** Submit the exact build that was tested and preserve evidence of what was approved.

- [ ] Upload the validated archive to App Store Connect.
- [ ] Wait for processing to complete.
- [ ] Resolve processing warnings and errors.
- [ ] Assign the processed build to an internal TestFlight group.
- [ ] Confirm TestFlight installation on real iPads.
- [ ] Select that exact build for the App Store version.
- [ ] Complete metadata, privacy, age-rating, export, and content-rights sections.
- [ ] Confirm screenshots and icon are correct.
- [ ] Confirm review notes and contact details are complete.
- [ ] Choose manual or automatic release.
- [ ] Decide whether phased release is appropriate.
- [ ] Submit for App Review.
- [ ] Record the submission timestamp and App Store Connect state.
- [ ] Treat review messages as external input; do not expose secrets or broaden automation permissions in response.

Do not rebuild from an untracked or modified working tree after the tested archive has been selected. If the binary changes, repeat the relevant validation and TestFlight checks.

## Release evidence record

For the final candidate, preserve a release record containing:

- Marketing version
- Numeric build number
- Git commit SHA
- Release tag
- Archive SHA-256
- Xcode version
- iOS SDK version
- Minimum supported iPadOS
- Bundle identifier
- Signing certificate fingerprint or identifier, not the private key
- Provisioning profile identifier, not the profile secret
- App Store Connect build identifier
- TestFlight processing result
- Device/tester evidence
- Privacy questionnaire decision
- Privacy-manifest decision
- Export-compliance decision
- Approved metadata snapshot
- App Review submission timestamp
- Final release state

Never store certificates, private keys, API private keys, passwords, or provisioning-profile secrets in this evidence record.

## Definition of App Store release ready

FiliusPad is ready for App Store submission only when all of the following are true:

- [ ] The final App Store Connect app record exists.
- [ ] The bundle ID is registered and matches the project.
- [ ] The app icon is present and verified in the archive.
- [ ] Store metadata and screenshots are complete and approved.
- [ ] Privacy disclosures match the shipped binary.
- [ ] Export compliance is answered and approved by the responsible owner.
- [ ] A signed Release archive validates successfully.
- [ ] The exact archive has been uploaded to TestFlight.
- [ ] The exact build has passed physical-iPad smoke testing.
- [ ] No release-blocking crash, data-loss, import/export, accessibility, or layout issue remains.
- [ ] Review notes provide a complete path through the app without private credentials.
- [ ] The release owner has approved the legal, privacy, export, pricing, territory, and release-mode decisions.

## Recommended next work in this repository

The next implementation slice should be a **release packaging and validation slice**, not another full UI test round:

1. Obtain product-owner approval for the existing app icon and first-release identity.
2. Run the manual unsigned IPA workflow and retain its package-validation report and hash.
3. Run the full hosted simulator matrix on the same candidate commit.
4. Run the real-iPad protocol, including Files-app integration and icon presentation.
5. Add or update a protected manual signed-archive workflow without changing unsigned CI.
6. Complete the privacy/API audit and export-compliance record.
7. Upload the first signed build to internal TestFlight.

## Official references

- Apple upcoming submission requirements: https://developer.apple.com/news/upcoming-requirements/
- Create an App Store Connect app record: https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Upload builds: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds-overview/
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Privacy manifests: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
- App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Export compliance: https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance
- App Store icon and screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/
- App Store Connect API: https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api
