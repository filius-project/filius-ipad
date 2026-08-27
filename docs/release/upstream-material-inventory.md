# Upstream Filius material inventory

**Status:** release evidence prepared; independent chain-of-title and third-party review remain open
**Updated:** August 27, 2026

This inventory records the upstream material visible in the current Filius on iPad release tree. It is deliberately conservative: it documents repository locations and the executed permission scope without claiming that every file has been independently mapped to a copyright holder.

## Executed permission scope

The executed Apple-platform additional permission is retained privately and represented publicly only by the SHA-256 attestation. It covers qualifying Filius material already incorporated from the following official upstream releases and qualifying future official stable tagged releases, subject to the agreement’s conditions:

| Version | Official tag | Commit |
|---|---|---|
| 2.10.1 | `v2.10.1` | `dcd965f6139baef4c27cc6d3cc34106f6bebda40` |
| 2.11.0 | `v2.11.0` | `d8af89fe354b83e03cc43ea179be6effa49f134f` |
| 2.12.0 | `v2.12` | `efcbb5576ed6d9ba2c661b281413329fab1b5e4c` |
| 2.12.1 | `v2.12.1` | `bb777da9b6b0fee5f7b453fcb2a6c5171d3e0c52` |
| 2.12.2 | `v2.12.2` | `7b913254e723342d622a03895ccf32689e80e8d1` |
| 2.13.0 | `v2.13.0` | `4c98c45894eddc34f95c238eedde6a706032738f` |

The agreement does not automatically cover unreleased development branches or individual development commits. New third-party dependencies and bundled tools retain their own license terms.

## Current repository locations

| Material | Current location | Review state |
|---|---|---|
| Upstream Java Filius source and resources | `javaversion/filius-master/` | Present; version/provenance mapping beyond the contract table remains to be reviewed |
| Upstream GPL texts | `GPLv2.txt`, `GPLv3.txt`, and `javaversion/filius-master/GPLv2.txt` / `GPLv3.txt` | Published in the repository; app copies are bundled under `ios/FiliusPad/Legal/` |
| Java-parity icons, screenshots, and graphics | `ios/FiliusPad/TopologyEditor/Assets/JavaParity/` | Present; exact asset-by-asset upstream mapping remains to be reviewed |
| FILIUS example and compatibility projects | `ios/FiliusPadTests/Fixtures/FLS/` and `javaversion/filius-master/beispiele/` | Present; fixture license/notice review remains open |
| Apple-specific Swift source, UI, persistence, and runtime behavior | `ios/FiliusPad/` outside `Assets/JavaParity/` | Independently maintained Apple edition code; contributor licensing terms are in `CONTRIBUTING.md` |
| Bundled Java runtime components | `javaversion/filius-master/java-runtime/` | Retains component-specific notices under `java-runtime/legal/`; third-party review remains open |
| Apple permission integrity attestation | `docs/legal/Filius-Apple-Permission.sha256` | SHA-256 only; no agreement text, addresses, signatures, or scan |
| Private executed scan | `/Users/macbookairm2/src/filius-on-ipad-prod/docs/legal/Filius-app-store-exception-signed.pdf` | Private evidence only; never commit or publish |

## Required follow-up before a public release

1. Review the exact release tree and archive contents against this inventory.
2. Complete the third-party notice/license review for the bundled Java runtime and any newly added assets or dependencies.
3. Preserve source/build instructions and the complete corresponding source required by the applicable GPL and the executed permission.
4. Keep the signed paper original and the private scan/hash archive outside Git.
5. Re-run the inventory after any upstream update, dependency addition, or asset change.

This document is evidence planning, not legal advice and not a substitute for the privately retained executed agreement.
