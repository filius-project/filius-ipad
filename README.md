# Filius on iPad

[![Project Readiness](https://github.com/filius-project/filius-ipad/actions/workflows/project-readiness.yml/badge.svg)](https://github.com/filius-project/filius-ipad/actions/workflows/project-readiness.yml)
[![Apple Release Readiness](https://github.com/filius-project/filius-ipad/actions/workflows/apple-release-readiness.yml/badge.svg)](https://github.com/filius-project/filius-ipad/actions/workflows/apple-release-readiness.yml)

Filius on iPad is a native SwiftUI network-topology editor and simulator for iPadOS. It provides touch-oriented design, configuration, simulation, documentation, and `.fls` project workflows compatible with desktop FILIUS.

This is the curated production repository. Historical parity artifacts, the bundled Java runtime, internal development plans, local credentials, and generated build evidence are intentionally excluded.

## Release status

| Area | Current state |
|---|---|
| Platform | iPadOS 17.0 and later |
| Implementation | Swift 5, SwiftUI, Foundation, UIKit, and WebKit; no third-party package dependencies |
| Version | 1.0 (build 1) |
| Localization | German, English, and French |
| Automated tests | XCTest/XCUITest locally and through manually triggered hosted simulator suites |
| Release compilation | Unsigned Release build on Xcode 26 / iOS 26 SDK |
| Distribution | Not yet approved for App Store distribution |
| Licensing | Separate Filius license and trademark permission are release blockers; see [LICENSE-STATUS.md](LICENSE-STATUS.md) |

The repository must remain private until the licensing gate in `LICENSE-STATUS.md` has been resolved and the public-source terms have been selected deliberately.

## Main capabilities

### Topology design

- Create and configure PCs, notebooks, switches, routers, gateways, and remote links.
- Connect device ports with LAN cables, including direct peer-to-peer connections.
- Move connected devices and pan or zoom the topology canvas.
- Open, import, save, and export FILIUS `.fls` projects.
- Recover work through native persistence and autosave handling.

### Network simulation

- Ethernet, ARP, IPv4, ICMP, UDP, and TCP behavior.
- Manual routing, RIP, DHCP, DNS, firewall rules, NAT, and port forwarding.
- Switch forwarding, packet inspection, interface inspection, routing diagnostics, and ping output.
- Deterministic simulation controls and adjustable simulation speed.

### Simulated applications

- Command line and virtual filesystem tools.
- File Explorer, Text Editor, and Image Viewer.
- Web Browser and Web Server using an isolated, JavaScript-disabled WebKit renderer.
- Simple Client and Echo Server.
- DNS Server, Email Client and Server, Personal Firewall, and Gnutella.
- An experimental constrained TCP/UDP protocol builder, disabled by default.

### Compatibility and safety

Known `.fls` content is mapped to native Swift models. Unknown JavaBean/XML content and supplemental archive entries are preserved within explicit size and count limits so malformed or oversized archives fail closed instead of causing unbounded processing.

The runtime network is simulated in memory. The production source does not create host network sockets or transmit topology data off the device. Imported files and issue attachments must nevertheless be treated as untrusted input.

## Build and run

Requirements:

- macOS with Xcode 26 or later for the current release toolchain;
- an iPad simulator with iPadOS 17 or later;
- Python 3 for repository validation scripts.

Open `ios/FiliusPad.xcodeproj`, select the shared `FiliusPad` scheme, and run it on an iPad simulator.

Command-line destination discovery:

```bash
xcodebuild \
  -project ios/FiliusPad.xcodeproj \
  -scheme FiliusPad \
  -showdestinations
```

Run the unit suite with the repository helper:

```bash
./scripts/mac/run-tests.sh --profile unit
```

## Validation

Run the fast repository checks:

```bash
python3 scripts/project/validate_project_readiness.py
python3 scripts/project/verify_localization.py --root .
python3 -m unittest discover -s scripts/project -p 'test_*.py'
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
```

Release-mode validation intentionally fails until all App Store, legal, privacy, export, signing, TestFlight, and real-device approvals have been completed:

```bash
python3 scripts/project/validate_project_readiness.py --release
```

The workflows are deliberately separated:

- **Project Readiness Contracts** validates repository structure, localization, release inventory, tests, and whitespace.
- **Apple Release Readiness** compiles an unsigned Release build for a generic iOS device.
- **Apple Simulator Tests** runs the selected XCTest/XCUITest release evidence suites manually.
- **Build Unsigned IPA** packages and hashes an unsigned IPA without receiving Apple credentials.

A successful unsigned build does not prove signing, TestFlight processing, App Store acceptance, or legal permission to distribute.

## Repository structure

| Location | Purpose |
|---|---|
| `ios/FiliusPad/` | Native application source and bundled runtime assets |
| `ios/FiliusPadTests/` | Unit and compatibility tests |
| `ios/FiliusPadUITests/` | UI and acceptance tests |
| `ios/scripts/` | Production packaging and document-contract verification |
| `scripts/` | Repository, localization, simulator, and release validators |
| `docs/` | Production operations, validation, release, legal, and readiness documentation |
| `release/` | App Store metadata inventory, compliance records, and staged release notes |
| `.github/` | Issue forms and least-privilege CI workflows |

## Documentation

- [Documentation index](docs/README.md)
- [Production-readiness review](docs/production-readiness-2026-07-31.md)
- [Apple simulator validation](docs/validation/apple-simulator-ci.md)
- [Real-iPad validation protocol](docs/validation/real-ipad-protocol.md)
- [App Store release readiness](docs/release/README.md)
- [License status](LICENSE-STATUS.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening work. Changes must preserve `.fls` compatibility and user data, include appropriate verification, and must not introduce signing assets, credentials, private keys, tokens, device identifiers, or personal data.

Until licensing is finalized, access to this private repository does not grant permission to publish, redistribute, sublicense, or submit the application to an app marketplace.
