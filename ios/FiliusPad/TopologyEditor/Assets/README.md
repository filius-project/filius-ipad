# Java Parity Assets (M002/S01)

This directory holds Java-derived visual assets used for the M002/S01 canvas/palette parity pass.

## Source of truth
- Manifest: `ios/FiliusPad/TopologyEditor/Assets/parity-asset-manifest.json`
- Source tree: `javaversion/filius-master/src/main/resources`
- Target tree: `ios/FiliusPad/TopologyEditor/Assets/JavaParity`

## Sync workflow
From repository root:

- Validate manifest/source integrity only:
  - `bash ios/scripts/sync-java-parity-assets.sh --check`
- Preview copy operations:
  - `bash ios/scripts/sync-java-parity-assets.sh --dry-run`
- Copy all manifest-declared assets:
  - `bash ios/scripts/sync-java-parity-assets.sh`

## Contract behavior
- Missing **required** assets fail with non-zero exit.
- Missing **optional** assets are logged as warnings.
- M002/S01 verification uses this manifest + sync script as the authoritative parity-asset contract.

## Scope
M002/S01 currently targets default icon mode and prioritized surfaces:
- Topology canvas
- Palette

Additional icon modes and broader surface coverage are deferred to later slices/milestones.
