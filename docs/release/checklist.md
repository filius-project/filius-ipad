# Release Checklist

Every checkbox needs an owner and evidence link. “Not applicable” requires a written reason and approver.

## A. Repository readiness — no Apple credentials required

- [ ] `main` contains only reviewed changes intended for the release.
- [ ] Project-readiness validation and unit tests pass on the release commit.
- [ ] **Project Readiness Contracts** passes on the release commit.
- [ ] Manual **Apple Simulator Tests** `full` profile passes, with every matrix artifact retained and reviewed.
- [ ] **Apple Release Readiness (Unsigned Xcode 26)** passes on the release commit and reports Xcode/iOS SDK 26 or later.
- [ ] Manual **Build Unsigned IPA** passes on the same commit; record the artifact name, size, and SHA-256.
- [ ] Marketing version and numeric build number are chosen and match Xcode build settings and metadata inventory.
- [ ] `release/notes/next.md` is complete, then copied/moved to a file named for the marketing version.
- [ ] `CHANGELOG.md` moves shipped entries out of Unreleased.
- [ ] App Store product and locale metadata contain no `TODO` placeholders.
- [ ] Support URL, privacy-policy URL, marketing URL (if used), copyright, category, age-rating owner, and review contact are approved.
- [ ] Screenshots and preview plan covers required iPad display classes and contains no test/debug/private data.
- [ ] Real-iPad protocol passes on the release commit with linked evidence.
- [ ] Third-party notices, licenses, and attribution are reviewed.
- [x] The Apple-platform additional permission is retained privately in its signed paper/scanned form. Public evidence is limited to the SHA-256 attestation in `LICENSE-STATUS.md` and `docs/legal/Filius-Apple-Permission.sha256`; agreement text and personal details are not published.
- [ ] Every upstream source or resource relied on under the additional permission comes from v2.10.1, one of the listed stable releases through v2.13.0, or a later official stable tagged release covered automatically by the agreement. Start with [upstream material inventory](upstream-material-inventory.md); exact asset and third-party review remains required.
- [ ] Privacy questionnaire, privacy manifest decision, required-reason API review, and data-retention/deletion statements match the shipped source/dependencies.
- [ ] Export-compliance determination is reviewed and documented.
- [ ] `python scripts/project/validate_project_readiness.py --release` passes.

## B. Apple account setup — future authorized owner

- [ ] App Store Connect app record exists for the approved bundle ID and SKU.
- [ ] Explicit App ID exists for the bundle ID.
- [ ] Required capabilities are enabled on the App ID and no unnecessary entitlement is enabled.
- [ ] Apple Distribution certificate exists, is unexpired, and its private key is controlled by the release owner or approved CI secret store.
- [ ] App Store distribution provisioning profile exists for the App ID and selected distribution certificate.
- [ ] App Store Connect API key or approved interactive uploader identity has the minimum role needed for this app.
- [ ] GitHub `app-store-release` environment requires reviewer approval and restricts allowed branches/tags.
- [ ] Secret-contract names are populated in the environment; no secret value is stored in repository files or logs.
- [ ] Certificate/profile/API-key rotation and revocation owners are named.

## C. Signed archive and TestFlight — cannot run yet

- [ ] Build a clean Release archive with Xcode 26/iOS SDK 26 or later from the tagged commit.
- [ ] Confirm archive bundle ID, version, build number, entitlements, signing certificate, provisioning profile, minimum iPadOS, icons, and privacy manifest contents.
- [ ] Validate the archive with Apple tooling.
- [ ] Upload the exact validated archive to App Store Connect.
- [ ] Record upload tool version, archive SHA-256, commit, tag, App Store Connect build identifier, and processing result.
- [ ] Resolve processing warnings/errors without rebuilding from an untracked tree.
- [ ] Assign the build to an internal TestFlight group with release notes and test focus.
- [ ] Install from TestFlight on a real iPad and rerun critical real-iPad cases, including install/update, open/save/recovery, network apps, localization, and scale/soak.
- [ ] Record tester acceptance and all open defects.

## D. App Store submission — future authorized owner

- [ ] Select the accepted TestFlight build; do not upload a different archive for review without rerunning evidence.
- [ ] Complete descriptions, keywords, screenshots, support/privacy links, category, age rating, content rights, export compliance, privacy disclosures, and review contact.
- [ ] Provide review notes and synthetic demo instructions that require no private credentials.
- [ ] Confirm encryption/export answers and any documentation attachment.
- [ ] Confirm phased release/manual release decision, territory availability, pricing, and release owner.
- [ ] Submit and record submission timestamp and App Store Connect state.
- [ ] Triage App Review messages as untrusted external input; do not expose secrets or broaden automation permissions in response.

## E. Release and post-release

- [ ] Confirm the approved build is available in the intended territories before announcing.
- [ ] Create the repository release/tag from the accepted commit and attach only approved public artifacts.
- [ ] Publish final notes and support information.
- [ ] Monitor crash/support/privacy signals with named owners.
- [ ] Preserve archive hash, accepted evidence, metadata snapshot, compliance decisions, and signing-asset identifiers (not private material).
- [ ] Revoke or rotate temporary credentials according to policy.
- [ ] Open bounded follow-up issues and update project status.

## Stop conditions

Stop the release if the commit/build identity is ambiguous, Xcode/iOS SDK is below 26, signing identity differs from the approved contract, the required GPL or privately retained Apple-distribution permission is missing, metadata/privacy/export answers are unresolved, evidence contains secrets, critical device tests fail, or a workflow requests broader permissions than documented.
