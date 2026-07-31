# Real-iPad Validation Protocol

Use this protocol to decide whether a specific FiliusPad commit is acceptable on physical iPad hardware. Simulator, source inspection, and unsigned CI results are useful prerequisites, but they do not count as real-device acceptance.

## 1. Outcomes

Each test case has exactly one outcome:

- **PASS**: every expected observation was demonstrated and the required evidence is attached.
- **FAIL**: an expected observation was not demonstrated, the app crashed/hung, data was corrupted, or evidence contradicts the expectation.
- **BLOCKED**: the test could not be run because a prerequisite was unavailable. BLOCKED is not PASS and must name the blocker.
- **NOT RUN**: intentionally omitted. Give a reason and obtain acceptance-owner approval before treating the session as release evidence.

A session passes only when all required cases pass and there are no open severity-critical or severity-high defects for the tested build.

## 2. Roles

- **Operator** installs the build, performs the steps, and captures evidence.
- **Witness/reviewer** checks that evidence identifies the build and supports each result. For a release candidate, this should be someone other than the author of the final code change when practical.
- **Acceptance owner** decides whether optional cases or documented deviations are acceptable.

One person may act as operator and witness for development checks. Record that fact rather than leaving the witness blank.

## 3. Required equipment and build identity

Prepare:

- A physical iPad capable of running the project's deployment target (currently iPadOS 17.0 or later).
- A Mac with an Xcode version that can build the checked-out project and a development-signing identity authorized for that device.
- A clean checkout of the exact commit under test.
- A USB connection for first install and log capture. Wi-Fi debugging may be used after trust is established.
- Screen recording enabled on the iPad and enough free storage for test documents.

Record before testing:

- Git commit SHA and whether the tree is clean.
- Xcode version and iOS SDK version.
- App marketing version, build number, and bundle identifier from the installed build.
- iPad model, iPadOS version, free storage, orientation, keyboard/pointer use, and display scaling.
- Install method and signing type. Never record certificate files, private keys, passwords, tokens, device UDIDs, account email addresses, or provisioning-profile contents in public evidence.

## 4. Build and install

1. Fetch the target commit and verify `git status --short` is empty.
2. Run repository validation:

   ```text
   python scripts/project/validate_project_readiness.py
   python -m unittest discover -s scripts/project -p "test_*.py"
   ```

3. On macOS, build the `FiliusPad` scheme for the connected iPad with development signing selected locally in Xcode. Do not commit team IDs or signing changes.
4. Install and launch from Xcode once. Capture the Xcode, SDK, commit, version, and build-number evidence before functional steps.
5. Remove any prior test installation unless the case explicitly validates upgrade or recovery behavior.
6. Disable notifications and unrelated overlays that could obscure evidence. Do not disable platform protections.

A development-signed device build is acceptable for this protocol. It is not evidence that App Store distribution signing or TestFlight upload works.

## 5. Test data and evidence handling

- Use synthetic names, addresses, email content, and project files.
- Do not use real credentials, private messages, production network captures, or personally identifying device/account screens.
- Store evidence in a directory named `<date>-<short-sha>-<device-model>`.
- Name artifacts `<case-id>-<step>-<short-description>.<ext>`.
- Keep the unedited original screenshot/video/log. Redacted copies may be filed publicly; retain originals in the approved private evidence store.
- Hash `.fls` fixtures and exported projects with SHA-256 when a test depends on exact input/output identity.
- A screenshot must show enough UI context to identify the observation. A log excerpt must include timestamps and the relevant subsystem without secrets.

Copy [the evidence template](templates/real-ipad-evidence.md) for the session.

## 6. Required test cases

### IPAD-01 — Clean install and launch

1. Install after removing the previous test build.
2. Launch in portrait, then rotate to landscape and back.
3. Background the app for at least 10 seconds and return.

Expected: the product shell appears without crash, launch-blocking alert, clipped primary controls, or loss of interaction. Rotation and foregrounding preserve a usable canvas.

Evidence: launch screenshot, landscape screenshot, and a short result note.

### IPAD-02 — Touch topology construction

1. Create a new topology using touch only.
2. Add at least a computer/notebook, switch, router, and gateway or remote-link device where available.
3. Move two devices, select/deselect them, connect valid endpoints, and attempt one invalid connection.
4. Delete one cable and one device.

Expected: gestures select the intended target, valid topology changes are visible, invalid connections fail safely with understandable feedback, and deletion leaves no orphaned visible connection.

Evidence: before/after screenshots and a short screen recording covering one add, move, connect, invalid connect, and delete sequence.

### IPAD-03 — Configuration and identity

1. Rename at least two devices.
2. Configure host and router interfaces with synthetic IP data.
3. Configure a switch and one router/gateway-specific setting exposed by the UI.
4. Close and reopen each editor.

Expected: supported values persist, validation rejects malformed values without corrupting previous settings, and device identity remains consistent on the canvas and in editors.

Evidence: configuration screenshots with synthetic values and the validation message for one rejected value.

### IPAD-04 — Simulation lifecycle and diagnostics

1. Start simulation.
2. Run ping and trace/path diagnostics between reachable hosts.
3. Run one unreachable-host diagnostic.
4. Stop and restart simulation.

Expected: lifecycle controls remain responsive; successful diagnostics identify deterministic responders/path information; unreachable results are bounded and understandable; restart does not duplicate stale runtime state.

Evidence: successful and unsuccessful diagnostic outputs plus lifecycle screenshots.

### IPAD-05 — Core network services

1. Exercise DHCP assignment on a small topology.
2. Resolve a synthetic hostname through DNS.
3. Exercise routing across at least two network segments.
4. Where configured, verify firewall and NAT/port-forwarding behavior with one allowed and one denied flow.

Expected: observed addresses, name resolution, routes, and policy decisions match the configured topology. Packet/message viewers remain navigable when available.

Evidence: configuration, result, and packet/message-view screenshots. Record expected and observed addresses/ports.

### IPAD-06 — Runtime applications

Exercise the installed applications relevant to the candidate, including simple client/echo server, web browser/server, email client/server, and Gnutella when present. For each tested application, cover launch, one successful interaction, one safe failure, close/reopen, and simulation stop/start.

Expected: applications use simulated network state, expose understandable errors, and do not crash or retain invalid sessions across lifecycle changes.

Evidence: one result screenshot per application and a table of endpoints, expected outcome, and observed outcome.

### IPAD-07 — Filesystem and terminal

1. Create directories and files through the terminal/filesystem surface.
2. List, read, rename/move, and remove synthetic content.
3. Run network inspection commands during simulation.
4. Close and reopen the application surface.

Expected: filesystem operations are deterministic and persist where specified; invalid paths fail safely; network inspection reflects the live topology.

Evidence: terminal transcript screenshots. Do not include host-machine paths or personal data.

### IPAD-08 — Open, save, and recovery

1. Open a known synthetic `.fls` fixture and record import warnings.
2. Make a supported edit and save to a new file.
3. Reopen the saved file and verify supported topology/runtime/application content.
4. Force-quit after a separate edit, relaunch, and observe autosave/recovery behavior.
5. Attempt to open one malformed or unsupported fixture.

Expected: supported content survives the round trip; warnings and unsupported content are attributed; recovery is understandable; malformed input does not crash or overwrite the source.

Important: this protocol does **not** claim byte-identical or lossless preservation of all Java archive content. That is the next M012 fidelity milestone and needs its own acceptance criteria.

Evidence: fixture hashes, import warning screenshot, saved-file hash, reopened result, and recovery/malformed-input evidence.

### IPAD-09 — Documentation, settings, and localization

1. Open documentation/help and information surfaces.
2. Change simulation speed/settings and confirm the observable effect.
3. Exercise German, English, and French UI where the build exposes them.
4. Check long labels in portrait and landscape.

Expected: help/settings surfaces are reachable, changes persist as designed, user-facing strings resolve without raw localization keys, and primary controls remain legible.

Evidence: one screenshot per locale plus settings before/after observations.

### IPAD-10 — Protocol application builder

1. Create a constrained TCP or UDP application definition.
2. Run a valid interaction between two devices.
3. Attempt an invalid schema or endpoint configuration.
4. Save, reopen, and rerun the valid application.

Expected: valid definitions execute predictably; invalid definitions are rejected without executing partial behavior; persisted definitions remain editable and runnable.

Evidence: definition, successful output, rejection feedback, and reopened definition.

### IPAD-11 — Multitasking and input modes

1. Test full screen and one supported Split View/Stage Manager size if available on the device.
2. Exercise primary flows with touch; repeat text entry with hardware keyboard if used in the target environment.
3. Connect a pointer/trackpad if available and verify it does not block touch behavior.

Expected: core controls remain reachable, text entry dismisses correctly, and resizing does not corrupt topology coordinates or leave blocking overlays.

Evidence: full-screen and compact-size screenshots and notes on attached input devices.

### IPAD-12 — Scale and soak

1. Build or open a synthetic topology of at least 20 nodes.
2. Pan/zoom/edit it, start simulation, and run repeated diagnostics for at least 10 minutes.
3. Save, background for at least one minute, return, and continue editing.

Expected: no crash, runaway thermal behavior, unrecoverable input lag, topology corruption, or unbounded diagnostics. Record observed responsiveness rather than estimating frame rates without tooling.

Evidence: topology screenshot, start/end timestamps, thermal-state observation if available, diagnostic count, and saved-file hash.

## 7. Session decision

A reviewer checks:

- Every required row has PASS/FAIL/BLOCKED/NOT RUN.
- Evidence names include case IDs and identify the tested build.
- Failures have linked issues.
- Re-runs reference the original failure and show the fixed commit.
- No evidence exposes secrets or personal data.

The reviewer signs the evidence template with name/identity, date, decision, and unresolved issue list.

## 8. Filing a failure

Use the **Real-iPad validation failure** issue form.

1. File one issue per independently fixable defect. Link related failures rather than combining them into an omnibus report.
2. Put the case ID and short symptom in the title, for example: `[IPAD-08] Reopened archive loses router route entry`.
3. Include commit, app version/build, Xcode/SDK, iPad model/iPadOS, clean-install state, and exact case step.
4. State expected and observed behavior. Do not write speculative root cause as fact.
5. Attach the smallest sanitized evidence set that demonstrates the defect. Provide hashes for private fixtures and state how an authorized maintainer can obtain them.
6. Select severity by impact, not urgency. A crash/data-loss/security issue is high; a cosmetic problem is normally medium/low.
7. Never attach signing assets, provisioning profiles, App Store Connect keys, account screenshots, UDIDs, or unredacted device logs.
8. Link the evidence session and mark the test row FAIL. After a fix, rerun the failed case and any named regression cases on the fix commit.
