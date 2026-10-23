# Publication readiness

## Principles

- Local source readiness requires successful build, scans, and independent review.
- Physical-device testing is a separate Primary Mac gate.
- Public visibility, releases, binaries, and app distribution need fresh owner approval.

## Current local status

- XcodeGen generation: passed on 2026-10-23.
- Unsigned generic iPhone build-for-testing: passed on 2026-10-23.
- Source, privacy, credential, prohibited-key, and artifact scans: passed with six exact historical attribution/provenance lines classified; five injected leak probes detected.
- Independent code/security/privacy QA: GO for private local staging on 2026-10-23.
- Independent documentation QA: GO for private local staging on 2026-10-23.
- Automated physical-device tests on Primary Mac: passed 217/217 with zero failures and zero skips on 2026-10-23.
- Owner-visible exploratory testing is separate from the automated suite and must be reported from the current publication cycle.

Evidence logs are retained in the private staging workspace, outside this source package. The private `libertyequalitydata/PersonalBrowser` repository and its first source push were owner-authorized and created on 2026-10-23. Before any public visibility change, complete a fresh owner-visible Primary Mac checklist, rerun current verification, and verify the repository's private security and conduct reporting channels. No release, binary, public visibility, or app distribution record is created by this milestone.
