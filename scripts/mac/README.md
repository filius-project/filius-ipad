# Mac simulator test runner

This directory provides a one-command Windows-to-Mac test workflow for `FiliusPad`.

## Prerequisites

- The Windows SSH alias `filius-mac` connects to the Mac.
- Xcode and an iOS simulator runtime are installed on the Mac.
- The Mac checkout exists at `~/src/filius`.
- For UI profiles, the `macbookairm2` desktop session must remain logged in. The runner launches UI tests through the Aqua session automatically.

## From Windows

Run a fast smoke test against the current Mac checkout:

```powershell
.\scripts\mac\run-tests.ps1 -Profile smoke -NoSync
```

Synchronize the Mac to the current committed and pushed Windows revision, then run everything:

```powershell
.\scripts\mac\run-tests.ps1 -Profile full
```

Run only unit tests:

```powershell
.\scripts\mac\run-tests.ps1 -Profile unit
```

Run all UI tests and download the result bundles and logs into ignored `tmp/` storage:

```powershell
.\scripts\mac\run-tests.ps1 -Profile ui -DownloadArtifacts
```

The synchronized mode deliberately rejects a dirty Windows checkout because uncommitted files cannot be fetched by the Mac. Use `-NoSync` when you intentionally want to test the checkout already present on the Mac.

## Profiles

| Profile | Tests |
|---|---|
| `smoke` | `ViewportTransformTests` plus the basic editor-launch UI test |
| `unit` | All `FiliusPadTests` |
| `ui` | All `FiliusPadUITests` |
| `runtime-ui` | Desktop, service, and simulation runtime UI suites |
| `desktop-ui` | Desktop application UI suite |
| `service-ui` | Runtime service application UI suite |
| `simulation-ui` | Runtime start/stop and simulation UI suite |
| `full` | Unit suite followed by the complete UI suite |

The full UI suite can take roughly an hour on the MacBook. The runner disables parallel simulator clones for stability.

## Artifacts

Mac artifacts are written outside the Git checkout:

```text
~/FiliusTestArtifacts/<timestamp>-<commit>-<profile>/
```

Each run preserves:

- Xcode and macOS toolchain information
- selected simulator JSON
- `xcodebuild` logs
- `.xcresult` bundles and JSON summaries
- a final simulator screenshot
- recent FiliusPad simulator logs
- tested Git commit and status

## Directly on the Mac

```bash
bash scripts/mac/run-tests.sh --profile smoke
bash scripts/mac/run-tests.sh --profile full --sync --branch main
```

If no iPad runtime is installed, explicitly permit the large download:

```bash
bash scripts/mac/run-tests.sh --profile smoke --install-runtime
```
