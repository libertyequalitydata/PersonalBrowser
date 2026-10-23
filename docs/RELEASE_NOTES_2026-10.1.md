# Personal Browser 2026-10.1

Initial public source snapshot of Personal Browser, an independent local-first iPhone browser starting point.

## Included

- SwiftUI and WebKit tabs, pinned tabs, Subtabs, Saved bookmarks, History, and Downloads.
- Separate persistent website sessions, owner-created Roles, and nonpersistent Incognito browsing.
- Reader, Library, Reader PDF export, document and media viewing, explicit transcription, and local Browsing Insights.
- Reversible site preferences and bounded site-specific interface adaptations.
- Maintainer, agent, privacy, security, build, architecture, and future-snapshot documentation.

## Important boundaries

- Source code only; no signed binary or separate beta distribution is included.
- No Default Browser entitlement, browser passkey authorization, Add to Home Screen capability, App Group, hosted backend, analytics, PIOS connection, or Core connection.
- Builders must use their own bundle identifier, signing team, security review, and any separately approved Apple capabilities.
- Future Personal Browser snapshots may not provide migration, API, history, or feature continuity with this release.

See [README.md](../README.md), [features and limitations](FEATURES_AND_LIMITATIONS.md), [build and signing](BUILD_AND_SIGNING.md), and [snapshot model](../SNAPSHOT_MODEL.md).
