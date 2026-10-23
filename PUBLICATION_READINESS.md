# Publication readiness

## Principles

- Local source readiness requires successful build, scans, and independent review.
- Physical-device testing is a separate Primary Mac gate.
- Public visibility, releases, binaries, and app distribution need fresh owner approval.

## Public release status

- Owner authorization: MIT licensing, Prifina and Liberty. Equality. Data. attribution, and public repository publication explicitly approved.
- XcodeGen generation: passed on 2026-10-24.
- Unsigned generic iPhone build-for-testing: passed on 2026-10-24 using Xcode 26.6.
- Source, privacy, credential, prohibited-key, and artifact scan: passed on 2026-10-24 with exact attribution, provenance, learning, and reporting references classified.
- Full Git-history credential, owner-path, signing-artifact, and build-artifact scan: passed on 2026-10-24.
- Independent code/security/privacy QA: GO for private local staging on 2026-10-23.
- Independent documentation QA: GO for private local staging on 2026-10-23.
- Automated physical-device tests on Primary Mac: passed 217/217 with zero failures and zero skips on 2026-10-23.
- Independent public-release review on 2026-10-24 found release-state documentation and reporting-channel blockers; those findings were remediated before publication.
- Final owner-visible release-candidate check: required immediately before repository visibility changes and recorded below.

### Owner-visible release-candidate check

- [x] App launches as Personal Browser with the independent globe artwork.
- [x] Onboarding does not summon the keyboard until an input is deliberately selected.
- [x] New Tab and an empty Library do not summon the keyboard unexpectedly.
- [x] A normal webpage opens; a second website session remains cookie-isolated; Incognito does not restore after relaunch.
- [x] Tabs, Saved, History, Reader, Library, Downloads, and About open without exposing commercial app data. The About page now deliberately identifies and links the maintained commercial edition without accessing its app data.
- [x] Add to Home Screen, browser passkey authorization, and Default Browser capability are absent in the source build and are explained in About and at relevant status/error surfaces.

Owner confirmation: all release-candidate checks passed on 2026-10-24. The capability-explanation copy added afterward changed no capability state, storage, network behavior, or browser function and passed a fresh source scan and unsigned test build.

Evidence logs are retained in private execution storage outside this source package. The source release contains no signed binary or app distribution record. GitHub private vulnerability reporting is enabled and verified immediately after the repository becomes public and before the release is announced.
