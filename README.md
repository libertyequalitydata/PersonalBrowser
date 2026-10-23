# Personal Browser

Personal Browser is an independent, local-first iPhone browser source snapshot periodically derived from the commercial Browser by Prifina. It may not match the current commercial product. Snapshot `2026-10.1` is a separate application with its own bundle identifier, storage, artwork, and unsigned build defaults.

## Choose the right edition

- **Try the maintained end-user app:** [Browser product site](https://browser.prifina.com/) · [Join the Browser beta in TestFlight](https://testflight.apple.com/join/VZZPdDXA)
- **Build or fork Personal Browser:** use this repository as an MIT-licensed starting point for your own browser.

The commercial app is the best way to test the continuously maintained product experience. This repository is a periodic source snapshot for builders; feature parity, migrations, and release continuity are not promised.

## What it includes

- SwiftUI and WebKit browsing with tabs, pinned tabs, Subtabs, bookmarks, history, and downloads.
- Separate persistent website sessions, optional owner-created Roles, and nonpersistent Incognito browsing.
- Reader, Library, Reader PDF export, document/media viewing, and explicit transcription actions.
- Local Browsing Insights and opt-in, reversible site settings.
- No required account, hosted backend, Core, PIOS, or AI service.

See [features and limitations](docs/FEATURES_AND_LIMITATIONS.md) for the exact snapshot boundary.

## Illustrative screens

These privacy-safe illustrations show the interaction model of this source snapshot. They are not App Store screenshots and may differ from a locally built version.

<p align="center">
  <img src="docs/images/new-tab.svg" width="240" alt="Illustrative Personal Browser new tab screen" />
  <img src="docs/images/tabs.svg" width="240" alt="Illustrative Personal Browser tabs screen" />
  <img src="docs/images/library.svg" width="240" alt="Illustrative Personal Browser Library screen" />
</p>

## Principles

- Browsing works without an account, hosted service, Core, or PIOS.
- Website sessions use separate WebKit stores; Incognito uses nonpersistent storage and is excluded from normal history and restoration.
- Saved items, Reader captures, downloads, and Insights are local unless the user explicitly exports or shares them.
- Managed Apple capabilities are absent in the default source build.
- Personal information is not collected for the source publisher by default.

## Build

Requires macOS with Xcode 26.3 or later and XcodeGen. Snapshot `2026-10.1` was verified with Xcode 26.6. The source target is iOS 17 or later.

```sh
xcodegen generate
xcodebuild -project PersonalBrowser.xcodeproj -scheme PersonalBrowser \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
python3 scripts/verify_public_snapshot.py
```

For device signing and test steps, see [build and signing](docs/BUILD_AND_SIGNING.md). The example source bundle ID is `org.libertyequalitydata.personalbrowser`; change it for your distribution. Apple managed entitlements, including Default Browser, do not transfer with source code.

## Documentation

- [Features and current limitations](docs/FEATURES_AND_LIMITATIONS.md)
- [Architecture and data boundaries](docs/ARCHITECTURE.md)
- [Maintainer guide](docs/MAINTAINER_GUIDE.md)
- [Build, signing, and physical-device verification](docs/BUILD_AND_SIGNING.md)
- [Default Browser entitlement boundary](docs/DEFAULT_BROWSER_ENTITLEMENT.md)
- [Agent startup prompt](docs/AGENT_START_PROMPT.md)
- [Privacy](PRIVACY.md), [security](SECURITY.md), and [contributing](CONTRIBUTING.md)

## Snapshot and license

The [MIT License](LICENSE) permits personal, open-source, and commercial derivatives. Future snapshots may be unrelated code drops with no shared ancestry, API, data migration, or compatibility continuity. There is no publication cadence or promise to release every commercial change. See [snapshot model](SNAPSHOT_MODEL.md) and [snapshot metadata](SNAPSHOT.json).

The source is provided without warranty, hosted service, support SLA, or release cadence. Derivatives must not imply endorsement by Prifina, Liberty. Equality. Data., Apple, or supported websites. Product names and commercial identity are not licensed by the MIT source grant.
