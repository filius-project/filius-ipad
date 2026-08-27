# M013 Experience Quality Acceptance

- **Milestone:** M013 — Experience Quality
- **Repository acceptance date:** July 26, 2026
- **Accepted implementation revision:** `f41f90e` (`fix: close M013 acceptance gaps`)
- **Implementation plan:** [Experience-Quality Implementation Plan](../experience-quality-implementation-plan.md)
- **Source evaluation:** [Java–Swift Experience Disparity Evaluation](../java-swift-disparity-evaluation.md)

## Decision

M013 is **accepted as a completed repository milestone**. Slices 1–9 are integrated, their shared simulator regression suite passes, the visual baselines were re-recorded in the canonical landscape pixel orientation and reviewed, localization remains complete in German, English, and French, and the bounded `.fls` compatibility gates remain green.

Physical-device acceptance remains a separate release-candidate dimension under the [Real-iPad Validation Protocol](../../validation/real-ipad-protocol.md). A development-signed smoke attempt on July 26, 2026 was blocked before test execution because the connected iPad needed to be unlocked and the local Xcode account credential was incomplete. This is not represented as a device PASS and does not replace the required per-candidate protocol.

## Accepted slices

| Slice | Accepted outcome |
|---|---|
| 1 — Executable visual baseline | Six deterministic XCUITest scenarios, reviewed PNG baselines, failure attachments, and an explicit `--record` gate. |
| 2 — Visual foundation and toolbar clarity | Shared experience tokens, adaptive regular/compact toolbar groups, clear mode state, and Java-derived Remote Link concept continuity. |
| 3 — Two-way Software Manager | Install, uninstall, reinstall, lifecycle cleanup, and deterministic diagnostics. |
| 4 — Keyboard commands and context menus | Editor commands and context actions route through the existing reducer behavior. |
| 5 — Adaptive hardware palette | Regular sidebar and compact device shelf/popover preserve the same placement actions. |
| 6 — Shared runtime workspace | Desktop and applications use one destination model, shared chrome, and an explicit Back to Desktop path. |
| 7 — Context-preserving configuration and inspection | Regular-width trailing inspector and compact fallback preserve topology context for configuration and packet inspection. |
| 8 — Responsive dense tables | Dense runtime tables adapt at compact widths without requiring two-axis navigation for primary operations. |
| 9 — Marquee selection and bulk editing | Empty-canvas marquee selection, move precedence, accessible selection state, and reducer-owned bulk deletion. |

## Runtime desktop follow-up

A final post-acceptance refinement aligns PC and notebook action mode more closely with the Java desktop model without changing the underlying runtime behavior:

- Endpoint IP address, subnet mask, gateway, and DNS remain owned by Design mode. Action mode no longer exposes a second editable endpoint-address form; the desktop taskbar instead provides read-only network information. Live DHCP client/server controls remain available because they represent runtime behavior rather than duplicate static configuration.
- Installed applications, protocol applications, and Software Manager now render as focused windows inside the device desktop. The Applications and Network controls remain visible while an application is open, and the existing Back to Desktop path is preserved. This intentionally follows Java's single-desktop/card-layout model rather than introducing draggable multi-window behavior on iPad.
- File Explorer and Image Viewer now track a current directory, open child folders, expose the current path, and navigate to the parent folder. File and image selection still uses the existing reducer callbacks and per-device virtual filesystem, so persistence and application functionality are unchanged.

## Completion-criteria evidence

| Criterion | Evidence |
|---|---|
| File, Mode, Simulation, and Help remain identifiable at regular and compact widths | Adaptive toolbar source contracts, `FiliusPadUITests.testRegularToolbarUsesAccessibleIconButtons`, compact touch-flow tests, and the reviewed empty-workspace baseline. |
| Executable visual gate with reviewed baselines and diffs | `ios/scripts/run-visual-regression.sh`; six 2360×1640 landscape baselines in `ios/FiliusPadUITests/ParityBaselines`; all six comparison tests passed at the `0.94` threshold. |
| Runtime software supports install/use/uninstall/save/reload/reinstall safely | Runtime desktop/service XCUITests, persistence XCUITests, reducer/XCTest coverage, and service/runtime Swift oracles. |
| Runtime desktop and applications use one navigation model | Runtime app-launch, desktop-suite, service-suite, and visual workspace tests. |
| Regular configuration/inspection preserves context with compact fallback | Regular inspector tests, compact configuration test, packet-viewer destination test, and visual baselines. |
| Dense views remain usable at 512 points and accessibility sizes | Compact-width source/verifier contracts and affected UI tests; shared content/action models are used across adaptive containers. |
| Keyboard, context-menu, and marquee workflows share reducer behavior with touch | Editor command implementations plus reducer and XCUITest coverage, including the full touch-flow and integrated acceptance suites. |
| German, English, and French remain complete | M011/S03 localization oracle: 830 keys with de/en/fr parity, interpolation/plural checks, and English fallback. |
| `.fls` compatibility and opaque preservation continue to pass | 382 XCTest cases, M012 contracts/static/syntax/Apple oracle phases, and the two-cycle lossless `.fls` oracle. |

## Verification record

The following commands passed on macOS 26.5.2 with Xcode 26.6 and the iPad (A16) iOS 26.5 simulator:

```text
python3 scripts/project/validate_project_readiness.py
python3 -m unittest discover -s scripts/project -p 'test_*.py'
python3 -m unittest ios.parity.tests.test_m005_s01_parity_inventory ios.parity.tests.test_m005_s01_gap_matrix
bash ios/scripts/verify-m011-s01.sh --phase contracts
bash ios/scripts/verify-m011-s02.sh --phase contracts
bash ios/scripts/run-m011-s02-swift-product-shell-settings-oracle.sh
bash ios/scripts/run-m011-s03-swift-localization-oracle.sh
bash ios/scripts/verify-m011-s04.sh --phase all
bash ios/scripts/run-m010-s05-swift-email-oracle.sh
bash ios/scripts/verify-m012-s01.sh --phase contracts
bash ios/scripts/verify-m012-s01.sh --phase oracle
bash ios/scripts/verify-m012-s01.sh --phase syntax
bash ios/scripts/verify-m012-s01.sh --phase apple-oracle
bash scripts/mac/run-tests.sh --repo <checkout> --profile unit --keep-simulator-running
bash scripts/mac/run-tests.sh --repo <checkout> --profile ui --keep-simulator-running --ui-timeout-minutes 120
```

Observed results:

- Project readiness: PASS; 65 intentional release placeholders remain.
- Project script tests: 16 passed.
- Parity inventory/gap tests: 38 passed.
- FiliusPad unit tests: **382 passed, 0 failed**.
- FiliusPad UI tests: **40 passed, 0 failed**.
- Focused simulation UI suite: **5 passed, 0 failed**.
- Focused runtime-service UI suite: **4 passed, 0 failed**.
- Visual regression suite: **6 passed, 0 failed** after reviewed baseline recording; normal comparison also passed in the full UI run.
- M011/S03 localization: **830 keys**, de/en/fr parity PASS.
- M012 lossless `.fls` Swift oracle: **2 cycles**, PASS.
- M010/S05 email oracle: PASS, including active DNS application gating and POP3 dot-unstuff/retrieval coverage.

### Runtime desktop follow-up verification — July 27, 2026

The final runtime-desktop refinement passed the complete simulator gates against the working tree based on `7bbfa9f`:

- Unit profile: **382 passed, 0 failed**.
- Complete UI profile: **40 passed, 0 failed**, including all six normal visual comparisons.
- Focused endpoint-configuration coverage: **2 passed, 0 failed**.
- Focused desktop-folder and service coverage: **3 passed, 0 failed**.
- Standalone visual comparison: **6 passed, 0 failed** after reviewing and recording the two intentional baseline changes.
- Localization oracle: **830 keys**, de/en/fr parity PASS.
- Final smoke profile: **6 unit smoke tests and 1 launch UI test passed, 0 failed**.

Durable local evidence links:

- `~/FiliusTestArtifacts/m013-runtime-followup-unit`
- `~/FiliusTestArtifacts/m013-runtime-followup-ui`
- `~/FiliusTestArtifacts/m013-runtime-followup-smoke`
- `~/FiliusTestArtifacts/m013-runtime-config-focused-4/runtime-config.xcresult`
- `~/FiliusTestArtifacts/m013-runtime-followup-focused/runtime-focused.xcresult`
- `~/FiliusTestArtifacts/m013-runtime-followup-visual-compare.xcresult`

Local untracked evidence directories:

- `~/FiliusTestArtifacts/2026-07-26-224109-0230140-ui`
- `~/FiliusTestArtifacts/2026-07-26-233439-0230140-unit`
- `~/FiliusTestArtifacts/2026-07-26-m013-visual-record.xcresult`
- `~/FiliusTestArtifacts/2026-07-26-m013-physical-smoke`

The simulator artifact names contain the pre-acceptance branch HEAD `0230140` because the closure fixes were still in the working tree during execution. Those tested changes were committed unchanged as `f41f90e`.

## Reviewed visual baselines

The six baselines accepted with the original milestone are:

- `device-inspector.png`
- `empty-design-workspace.png`
- `packet-viewer.png`
- `populated-design-workspace.png`
- `runtime-command-prompt.png`
- `simulation-desktop.png`

A seventh post-acceptance baseline, `runtime-software-manager.png`, protects the July 27 desktop-window refinement for application installation. The July 28 runtime refinement updates the desktop, Software Manager, CMD, and packet-viewer baselines for full-screen device presentation. It also gives CMD dedicated terminal chrome, a persistent working-directory prompt, and Linux-style deterministic `ping` transcripts while retaining the existing command and network behavior. All baselines use the canonical 2360×1640 landscape pixel dimensions; normal comparisons require at least the `0.94` similarity threshold and retain actual, expected, and difference attachments.

## Follow-ups and boundaries

- The [Interactive Product Tour](../interactive-product-tour-follow-up.md) remains an approved follow-up. M013 intentionally ships the shorter Quick Introduction rather than the live coach-mark tour.
- The [Protocol Lab Decision Gate](../protocol-lab-gate-decision.md) was not satisfied, so that work remains outside M013.
- Real-iPad validation is still required for each release candidate. The July 26, 2026 smoke attempt is **BLOCKED**, not PASS.
- Signing, TestFlight, App Store metadata, privacy/export approval, and release authority remain outside this repository milestone.
