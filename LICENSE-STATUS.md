# License status and distribution gate

**Status: unresolved — private repository only**

No final public license has been selected for Filius on iPad. This file is a release gate and is not itself a software license.

## Current position

- The iPad application was developed as an adaptation of the Filius network simulator.
- The application contains source concepts, compatibility behavior, `.fls` fixtures, and visual assets originating from Filius.
- `ios/FiliusPad/TopologyEditor/Assets/JavaParity/` contains files that are byte-identical to resources in the upstream Filius distribution.
- The application currently displays the upstream “GPLv2 or GPLv3” license wording. That presentation must be reviewed and changed if a separate license is signed.
- The Filius maintainer has indicated willingness to authorize App Store distribution, but the signatory’s authority over every covered contribution and asset must be documented.

## Required before any public release

1. Identify the exact upstream Filius repository revision and all covered files, resources, fixtures, and documentation.
2. Confirm which persons or entities own or control the relevant copyrights.
3. Execute either:
   - a separate license permitting this iPad project to be distributed under terms selected by Sören Schröder; or
   - a GPL distribution agreement with a personal App Store exception.
4. Execute a separate permission for the Filius name, logo, icons, and other project identifiers where necessary.
5. Update the app’s Information screen, repository notices, App Store metadata, and website so they state the signed license accurately.
6. Add the final signed/public license notice to this repository.
7. Review every future external contribution under terms compatible with Apple distribution and the selected project license.

## Interim restrictions

Until the above gate is completed:

- keep this repository private;
- do not submit the app to the App Store or TestFlight for external distribution;
- do not publish a source archive or binary release from this repository;
- do not describe Filius on iPad as unrelated to or non-derived from Filius;
- do not assume that maintainer status alone proves ownership of all contributions.

The unsigned legal templates are stored under `docs/legal/` for later review and signature.
