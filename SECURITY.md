# Security policy

## Reporting a vulnerability

Do not open a public issue for suspected vulnerabilities, malicious `.fls` samples, credentials, personal data, signing material, or exploit details.

Use one of these private channels:

1. GitHub private vulnerability reporting for this repository; or
2. email `support@filius.app` with the subject `Security report: Filius on iPad`.

Include the affected version or commit, reproduction steps, expected and observed behavior, and sanitized evidence. Do not send Apple certificates, provisioning profiles, App Store Connect credentials, account screenshots, device UDIDs, or unrelated personal information.

## Scope

Security reports may cover:

- malformed or oversized `.fls` project handling;
- archive traversal or unsafe file import/export behavior;
- data loss or unintended disclosure of topology projects;
- WebKit content-isolation bypasses;
- workflow or release-automation vulnerabilities;
- dependency or toolchain integrity issues.

The simulated network does not intentionally connect to the host network. A path that allows simulated traffic or imported HTML to escape into real network access is security-sensitive.

## Response

Reports will be acknowledged as time permits. Confirmed issues will be prioritized according to user impact, exploitability, and data-loss risk. No public disclosure date is promised until a fix and release path are available.
