# Apple simulator CI

The `Apple Simulator Tests` workflow provides optional hosted runtime evidence for FiliusPad. Local Mac testing is the primary development loop; the hosted workflow is intentionally manual so ordinary pushes do not start a long macOS test run.

## Starting a run

Start the workflow with `workflow_dispatch` and select a profile:

| Profile | Hosted jobs |
|---|---|
| `full` | Unit, editor UI, visual regression, persistence UI, app-launch/ping UI, desktop UI, service UI, and simulation UI |
| `unit` | Complete `FiliusPadTests` target |
| `editor-ui` | Basic launch, editor touch flow, infrastructure parity, and integrated acceptance UI suites |
| `visual-ui` | Six deterministic visual-regression comparisons against the reviewed iPad baselines |
| `persistence-ui` | Open, save, autosave, recovery, and document-picker UI suite |
| `runtime-ui` | App-launch/ping, desktop, service, and simulation UI jobs |
| `app-launch-ping-ui` | Runtime app launch and ping workflow suites |
| `desktop-ui` | Desktop application suite |
| `service-ui` | Runtime service application suite |
| `simulation-ui` | Simulation start/stop and runtime suite |

Use `full` for a release candidate. Smaller profiles are useful for hosted diagnostics after a local failure cannot be reproduced.

## Why the full suite is split

The previous workflow ran every unit and UI test serially in one job. Successful runs took roughly 90–100 minutes, and a later run lost its hosted runner after almost two hours. The manual full profile now distributes coverage across smaller jobs with `fail-fast: false` and a limited parallelism of three. A failing or disconnected runner therefore does not discard all other test evidence.

Each job:

1. Uses the repository's `macos-26` runner contract.
2. Records Xcode, simulator SDK, destinations, and available CoreSimulator devices.
3. Selects and boots an available iPad from the newest installed iOS runtime.
4. Runs only its assigned XCTest/XCUITest classes serially.
5. Uploads its own `.xcresult`, build log, screenshot, selected-device record, and recent simulator log.

## Evidence artifacts

Each matrix job publishes:

```text
FiliusPad-simulator-<profile>-<run-id>-<run-attempt>
```

Artifacts are retained for 14 days. A `full` release run is accepted only when every matrix job is green and its result bundle is available for review.

## Acceptance boundary

Hosted simulator evidence supplements but does not replace the physical-iPad validation protocol. Do not claim release readiness from compilation or simulator tests alone.

## Local equivalent

The preferred local interface is:

```powershell
.\scripts\mac\run-tests.ps1 -Profile unit -DownloadArtifacts
.\scripts\mac\run-tests.ps1 -Profile ui -DownloadArtifacts
```

For targeted development work, use profiles such as `desktop-ui`, `service-ui`, `simulation-ui`, or `runtime-ui`. Run the local `full` profile before a release candidate when time permits, then use the GitHub `full` matrix as independent committed-state evidence.
