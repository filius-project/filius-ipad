# Project Roadmap

The roadmap records accepted product/parity milestones, not every branch or implementation commit. Detailed slice evidence remains beside the iOS parity fixtures and verifiers.

| Milestone | Outcome | Status | Durable evidence |
|---|---|---|---|
| M001 | Native iPad topology editor, deterministic simulation baseline, persistence/recovery, integrated touch acceptance, and unsigned IPA packaging foundation | **Completed** | Initial `verify-s01.sh` through `verify-s05.sh`, Xcode tests, and unsigned workflow history |
| M002 | Visual/recovery parity foundation and path-aware runtime diagnostics with a transitive closure verifier | **Completed** | M002 verifier chain and [requirements coverage](milestones/M002-requirements-coverage.md) |
| M003 | DHCP/DNS service parity, service lifecycle, and hostname-aware routing contracts | **Completed** | M003 verifier chain |
| M004 | Java `.fls` import compatibility seams, workflow, and attributed legacy/unsupported-content reporting | **Completed** | M004 verifier chain |
| M005 | Broad Java network/runtime fidelity: topology inventory, routing, Ethernet/ARP/IP/ICMP, UDP/RIP/DHCP/TCP, firewall, NAT, port forwarding, packet viewers, and integrated router/gateway closure | **Completed** | M005 parity matrix, slice records, fixtures, and verifier chain |
| M006 | Canonical parity-chain repair, unsigned IPA workflow hardening, structured CI evidence, and router/gateway acceptance closure | **Completed** | M006 slice records and runtime validation policy |
| M007 | Named/configurable devices, complete topology editing, real Open/Save archives, and Java fixture corpus | **Completed** | M007 slice records and archive/corpus oracles |
| M008 | Router/gateway construction workflows, switch fidelity, notebook identity, and native remote-link replacement | **Completed** | M008 slice records and Swift oracles |
| M009 | Persistent virtual filesystem, terminal filesystem commands, complete `.fls` document archive workflows, and live terminal/network inspection | **Completed** | M009 slice records, review-fix evidence, and Swift oracles |
| M010 | Simulated runtime applications and protocols: simple client/echo, DNS, web browser/server, host firewall, email, and Gnutella | **Completed** | M010 slice records, protocol/runtime oracles, and accepted CI evidence |
| M011 | Documentation mode, product shell/settings/simulation speed, German-English-French localization, and constrained protocol application builder | **Completed** | M011 slice records, localization verifier, and Swift oracles |
| M012 | Bounded lossless `.fls` preservation for unknown JavaBean/XML and supplemental archive content, with native-edit precedence and fail-closed safety limits | **Completed** | M012/S01 fixture, static verifier, two-cycle Swift oracle, XCTest coverage, full Java configuration corpus, and accepted Apple CI |
| M013 | Adaptive experience quality: executable visual regression, clearer toolbar and palette, two-way software management, shared runtime navigation, context-preserving inspectors, responsive dense views, keyboard/context actions, and marquee editing | **Completed** | [M013 acceptance](milestones/M013-experience-quality-acceptance.md), reviewed visual baselines, 382 unit tests, and 40 UI tests |

## Status vocabulary

- **Completed** means the milestone's tracked slice evidence and regression chain were accepted into the current repository lineage.
- **Next** means planned work that must not be represented as accepted behavior.
- **In progress** work must link its active plan and must not replace accepted evidence with branch-only claims.

## Planning rule

The tracked M001-M013 product/parity chain is complete. New parity defects must be filed with reproducible evidence and closed with focused regression coverage; physical-device validation and Apple release readiness remain separate acceptance dimensions.
