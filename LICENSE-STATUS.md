# License status and distribution gate

**Status: executed Apple-platform additional permission privately archived; App Store release gates remain open**

This file is a release record, not a standalone software license. Filius on iPad remains an independently maintained adaptation of Filius. Covered Filius material continues to be available under the applicable GNU General Public License, version 2 or version 3, at the recipient’s choice. The executed additional permission supplements that GPL choice for Apple-platform and project-controlled distribution.

## Private permission record and public integrity attestation

The fully signed agreement and its paper originals are retained privately. The agreement text, signatures, postal addresses, and scan are intentionally not published.

- Public integrity record: [`docs/legal/Filius-Apple-Permission.sha256`](docs/legal/Filius-Apple-Permission.sha256)
- SHA-256 of the privately retained signed scan: `9827ca00c24c861644e10f0b6c39aa5deeb7cf8966f79f69070fcb7868ad9d75`
- App-bundled record: `Apple-Platform-Additional-Permission.sha256` (hash only)

The fingerprint permits byte-for-byte comparison with the privately retained scan without exposing the agreement. It is an integrity attestation, not a publication of the contract.

## Required attribution and project status

The app, public repository, documentation, and website must state prominently:

> Based on Filius by Dr. Stefan Freischlad and the Filius project.

They must also state that Filius on iPad is independently maintained and is not published, operated, or officially supported by the original Filius project. The project may use the authorized Filius names, icons, screenshots, graphics, and the `filius.app` domain to the extent covered by the privately retained permission, without implying official publication or support by the original project.

## Continuing obligations

- Keep the applicable GPL terms and complete corresponding source available as required by the GPL and the executed permission.
- Keep the hash-only integrity attestation accessible in the repository and the app’s legal information.
- Review third-party dependencies and bundled tools under their own license terms; the additional permission does not replace them.
- Require compatible licensing language for future contributions before accepting them.
- Keep the legal owner, privacy, export-compliance, Apple account, signing, device, metadata, and App Review gates separately evidenced.

## Publication decision

The executed permission resolves the previously tracked missing Apple-distribution permission gate. The agreement itself remains private. The hash attestation does not establish Apple account access, signing credentials, App Store Connect readiness, privacy/export approvals, real-iPad acceptance, or App Review approval. Those remain release blockers until separately evidenced in `docs/release/checklist.md`.
