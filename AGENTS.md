# AGENTS.md — Personal Browser

Instructions for coding agents and maintainers working in this repository.

## Product and repository model

Personal Browser is an independent, local-first iPhone browser source snapshot. It is not a continuously synchronized mirror of another product. Every published snapshot must be treated as a bounded source release with its own verification, documentation, and migration claims.

The default project is intentionally unsigned and uses an example bundle identity. It must remain useful without an account, hosted service, PIOS connection, managed Apple entitlement, or proprietary backend.

## Authority order

1. The current human owner or repository maintainer.
2. This file and the repository documentation.
3. Current source code and tests.
4. Historical snapshot notes and commit messages.

When these conflict, stop and surface the conflict. Do not infer permission to publish, change repository visibility, create releases, distribute builds, or activate managed capabilities.

## Hard boundaries

- Keep commercial credentials, identities, signing records, distribution records, device identifiers, personal browsing data, and private evidence out of the repository.
- Keep the default source project free of signing teams, provisioning profiles, managed entitlements, App Groups, and hosted-service secrets.
- Keep website sessions isolated. Incognito must use nonpersistent WebKit storage and stay out of normal restoration, history, and Insights.
- Treat URLs, page text, downloaded files, metadata, JavaScript messages, and extracted Reader content as untrusted input.
- Do not claim a website-specific adaptation is generally reliable. Websites can change without notice.
- Do not claim tests passed unless they ran in the current change cycle. The historical 217/217 physical-device result belongs only to snapshot 2026-10.1.
- Do not use Simulator as a substitute for requested physical-device verification. Do not launch Simulator unless the maintainer explicitly asks for it.
- Do not publish or expose the repository, tag a release, upload a binary, or create app distribution records without explicit authorization.

## Repository map

- `project.yml` — authoritative XcodeGen project definition and source-only build identity.
- `Browser/Sources/App/` — app entry point, central store, passkey gate, and Home Screen capability gate.
- `Browser/Sources/Models/` — persisted and in-memory browser models.
- `Browser/Sources/Persistence/` — JSON snapshot and local file persistence.
- `Browser/Sources/Views/` — SwiftUI browser shell, tabs, Reader, Library, Insights, settings, onboarding, and About.
- `Browser/Sources/Web/` — WebKit bridge, navigation policy, downloads, site preferences, URL handling, and browser chrome behavior.
- `Browser/Sources/Media/` — document viewing, media playback, transcription, and Reader PDF export.
- `Browser/Tests/` — unit and WebKit-focused regression tests.
- `docs/` — architecture, build, maintenance, feature boundary, and agent handoff documentation.
- `scripts/verify_public_snapshot.py` — source-package boundary scanner. Update it deliberately when adding required public files or classified historical references.

## Required working sequence

1. Read `README.md`, `docs/FEATURES_AND_LIMITATIONS.md`, `docs/ARCHITECTURE.md`, `docs/MAINTAINER_GUIDE.md`, and the files in the affected area.
2. Inspect `git status` and preserve unrelated changes.
3. State a concrete plan before changes spanning more than two files or shared behavior.
4. Make the smallest coherent change. Use `project.yml` rather than editing the generated Xcode project.
5. Add or update tests for behavior changes and update documentation when boundaries or user-visible behavior change.
6. Run the boundary scanner and the proportional build/test set.
7. Report exactly what ran, what did not run, and any remaining risk.

## Standard commands

```sh
xcodegen generate
python3 scripts/verify_public_snapshot.py
xcodebuild -project PersonalBrowser.xcodeproj -scheme PersonalBrowser \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

For a signed physical-device run, follow `docs/BUILD_AND_SIGNING.md`. Never commit signing changes or generated build products.

## Change-impact rules

- Persisted model changes require backward-compatible decoding or an explicit migration/reset decision, plus tests.
- WebKit navigation, session, Incognito, link-opening, app-handoff, download, and JavaScript changes require focused regression tests and physical-device testing when practical.
- Reader extraction, PDF, media, and transcription changes require tests with untrusted or malformed inputs and user-visible failure states.
- Privacy manifest, Info.plist, bundle identity, capability gate, or entitlement changes require a full boundary scan and explicit maintainer review.
- Site-specific adaptations must be bounded by host, reversible in settings, and fail open to the normal website rather than trap navigation.
- New documentation assets must be privacy-safe and classified by the source scanner.

## Verification matrix

- Documentation-only: boundary scanner; validate links and rendered Markdown.
- Swift logic/model: boundary scanner, relevant unit tests, unsigned generic build.
- WebKit/navigation/session: boundary scanner, relevant WebKit tests, unsigned build, physical-device smoke test.
- Persistence/privacy/capability: full tests, unsigned build, source scan, independent review, physical-device verification.
- Release/publication: all of the above plus owner authorization, repository security-channel check, redaction review, and current release notes.

## Commit and review expectations

- Keep commits scoped and describe the user-visible or boundary effect.
- Do not mix source cleanup with behavior changes unless required for the same outcome.
- A pull request should include the tests run, device testing actually performed, privacy/security impact, and documentation changes.
- Independent review is expected before publication, security-sensitive changes, capability activation, or a new periodic snapshot.

## Stop and ask

Stop and ask the maintainer before changing repository visibility, licensing, attribution, bundle ownership, Apple managed capabilities, data-sharing architecture, hosted services, analytics/telemetry, or public distribution. Also stop when source provenance or permission to include an asset is unclear.
