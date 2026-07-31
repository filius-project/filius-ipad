# Signing and Secret Contract

This document defines the inputs a future release workflow may consume. It does not supply those inputs and does not authorize creation of a signed workflow.

## Required Apple objects

An authorized Apple account owner must create and approve:

1. An explicit App ID for the final bundle identifier, with only required capabilities.
2. An Apple Distribution certificate and its private key, or an approved alternative signing model documented before implementation.
3. An App Store distribution provisioning profile binding the App ID and distribution certificate.
4. An App Store Connect app record with approved SKU, bundle ID, ownership, roles, metadata, and compliance answers.
5. An App Store Connect API key with the minimum role required for build upload/management, or an approved interactive upload identity.

These objects are account state. A repository file cannot prove that they exist or are valid.

## Future GitHub environment

Use an approval-protected environment named `app-store-release`:

- restrict it to protected release tags/branches;
- require a human reviewer who owns release authority;
- store release secrets only at environment scope;
- keep pull-request and issue workflows unable to reference the environment;
- prohibit self-approval by the code author where repository policy supports it.

The canonical names are in `release/signing/secret-contract.json`.

### Non-secret variables

- `APPLE_TEAM_ID`
- `IOS_APP_ID`
- `IOS_BUNDLE_ID`

Identifiers are not private keys, but environment scope prevents accidental divergence and keeps release configuration reviewable.

### Secrets

- `IOS_DISTRIBUTION_P12_BASE64`: base64-encoded PKCS#12 containing the approved Apple Distribution certificate and private key.
- `IOS_DISTRIBUTION_P12_PASSWORD`: password for that PKCS#12.
- `IOS_APP_STORE_PROFILE_BASE64`: base64-encoded App Store distribution provisioning profile.
- `APP_STORE_CONNECT_KEY_ID`: API key identifier.
- `APP_STORE_CONNECT_ISSUER_ID`: issuer identifier.
- `APP_STORE_CONNECT_PRIVATE_KEY_P8_BASE64`: base64-encoded `.p8` private key.

If a future design eliminates one of these inputs, update the contract and threat model before changing automation. Never retain unused credentials “just in case.”

## Handling requirements

A future signed workflow must:

- trigger only from an authorized manual dispatch or protected release tag, never from issue/comment text or untrusted pull-request code;
- use explicit least-privilege permissions and no repository administration permission;
- decode secrets only under `$RUNNER_TEMP` with restrictive permissions;
- create an ephemeral keychain, import only the intended identity, set a bounded key partition list, and delete the keychain in an `always()` cleanup step;
- install the provisioning profile into a temporary/standard CI location and remove it in cleanup;
- never print decoded values, `security find-identity` details beyond the approved fingerprint, provisioning-profile contents, environment dumps, or command tracing containing secrets;
- pin and review third-party actions before allowing them near release credentials;
- validate archive bundle ID, version/build, entitlements, certificate fingerprint, profile UUID/name, commit, and SHA-256 before upload;
- upload exactly the validated archive and persist only non-secret evidence;
- rotate/revoke credentials after suspected exposure and record the incident privately.

## Separation of duties

An agent may prepare metadata, validation, and a candidate workflow without secrets. It may not create Apple account objects, approve the release environment, retrieve credentials, sign, upload, submit, accept legal/export/privacy attestations, or merge its own release change unless a maintainer explicitly grants that authority outside issue text.
