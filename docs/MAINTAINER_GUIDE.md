# Maintainer guide

## Source of truth

`project.yml` is the project definition. Generate the Xcode project with XcodeGen and do not commit the generated project. The current code and tests govern behavior; snapshot notes describe only the release in which they were written.

## Code map and change impact

| Area | Primary files | Review focus |
|---|---|---|
| App lifecycle and state | `Browser/Sources/App/BrowserApp.swift`, `BrowserStore.swift` | restoration, selected tab, foreground timing, capability gates |
| Models and persistence | `BrowserModels.swift`, `BrowserPersistence.swift` | compatible decoding, migration, retention, Incognito exclusion |
| Browser shell | `BrowserRootView.swift`, `TabOverviewView.swift`, `BrowserTheme.swift` | keyboard/focus, full-screen surfaces, minimized controls, accessibility |
| WebKit | `WebPage.swift`, `WebView.swift`, `URLResolver.swift` | navigation policy, popup/subtab behavior, sessions, downloads, untrusted messages |
| Site preferences | `SiteAccessibilityPreferences.swift`, `SiteLinkOpeningPreferences.swift`, `AppPromptPreferences.swift` | host scoping, reversibility, redirect loops, safe fallback |
| Reader and Library | `ReaderView.swift`, `LibraryView.swift`, `ReaderPDFExport.swift` | extraction quality, source attribution, explicit retention/export |
| Media and files | `BrowserMediaPlayback.swift`, `BrowserDocumentViewer.swift`, `BrowserTranscription.swift` | codecs, audio session, background behavior, malformed files, permissions |
| Privacy boundary | `Info.plist`, `PrivacyInfo.xcprivacy`, `project.yml` | capabilities, collected data, signing, prohibited keys |

## Persisted-data changes

The app stores a JSON snapshot and related files in its own Application Support namespace. When changing a persisted model:

1. Decide whether old data must decode, migrate, or be deliberately reset.
2. Prefer additive fields with defaults and tolerant decoding.
3. Add fixtures or tests for the previous shape and the new shape.
4. Confirm Incognito and temporary overlay state do not enter durable collections.
5. Document any user-visible reset or incompatibility.

Future independent snapshots must not claim migration compatibility unless it has been implemented and tested for the exact pair of snapshots.

## WebKit and site adaptations

- Scope preferences to a normalized host or clearly documented site family.
- Distinguish internal navigation from an external destination before applying link-opening policy.
- Prevent an overlay Subtab decision from also navigating the underlying tab.
- Treat redirect intermediaries as part of a site flow only when verified and bounded.
- Keep installed-app handoff choices user-controlled and reversible.
- Injected JavaScript must tolerate missing elements, repeated execution, and navigation changes.
- Never freeze scrolling or remove the site's only navigation path while suppressing a prompt.

## Privacy and security review

Before merging changes that affect retention, permissions, network destinations, scripts, downloaded content, or sharing:

- inspect the data source, destination, purpose, retention, and deletion path;
- confirm the privacy manifest and usage descriptions remain accurate;
- check that content is escaped or parsed safely rather than treated as instructions;
- keep credentials and personal test data out of fixtures and logs;
- run `python3 scripts/verify_public_snapshot.py`.

## Verification workflow

For every substantive source change:

```sh
xcodegen generate
python3 scripts/verify_public_snapshot.py
xcodebuild -project PersonalBrowser.xcodeproj -scheme PersonalBrowser \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
```

Run the affected tests and then the complete test bundle when behavior crosses components. A generic build compiles tests but does not execute them. Follow `docs/BUILD_AND_SIGNING.md` for a signed physical-iPhone run and report the exact pass/fail result from the current cycle.

## Pull request checklist

- [ ] User-visible behavior and rationale are described.
- [ ] Privacy, security, persistence, and Incognito impact are stated.
- [ ] Relevant tests were added or updated.
- [ ] Boundary scanner passed.
- [ ] Unsigned generic build passed.
- [ ] Physical-device testing is reported accurately, including when not run.
- [ ] Documentation and screenshots still match the implemented snapshot.
- [ ] No signing, credential, device, browsing, or private evidence material is included.

## Creating a future periodic snapshot

Treat each future snapshot as a fresh curation milestone:

1. Select a verified source baseline and record its provenance privately.
2. Copy source only; exclude Git history, signing, distribution, website, account, device, and owner data.
3. Assign independent bundle/storage identities and unsigned defaults.
4. Remove proprietary integrations, automatic organization-specific behavior, secrets, and managed capabilities.
5. Update license, provenance, privacy, limitations, changelog, screenshot, and snapshot metadata.
6. Extend the boundary scanner for new file types and exact classified historical references.
7. Run leak probes, full tests, generic build, physical-device checks, and independent code/documentation review.
8. Obtain explicit authorization before repository creation, visibility changes, tags, releases, binaries, or distribution.

Do not overwrite an older immutable snapshot to simulate continuity. Use a new branch, tag, repository history decision, or separately documented code drop.
