# Personal Browser

Personal Browser is an independent, local-first iPhone browser source snapshot periodically derived from the commercial Browser by Prifina. It may not match the current commercial product. This October 2026 snapshot is a separate application with its own bundle identifier, storage, simple artwork, and unsigned build defaults.

## Principles

- Browsing works without an account, hosted service, Core, or PIOS.
- Website sessions use separate WebKit stores; Incognito uses nonpersistent storage and is excluded from normal history and restoration.
- Saved items, Reader captures, downloads, and Insights are local unless the user explicitly exports or shares them.
- Managed Apple capabilities are absent in the default source build.

## What is included

SwiftUI and WebKit tabs, owner-created website sessions and Roles, bookmarks, history, Incognito, Reader, Library, downloads, local Browsing Insights, and opt-in site settings. Website-specific adjustments can break when websites change. See [architecture](docs/ARCHITECTURE.md) and [privacy](PRIVACY.md).

## Build

Requires macOS with Xcode 26.3 and XcodeGen. The source target is iOS 17 or later.

```sh
xcodegen generate
xcodebuild -project PersonalBrowser.xcodeproj -scheme PersonalBrowser \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
python3 scripts/verify_public_snapshot.py
```

For device signing and test steps, see [build and signing](docs/BUILD_AND_SIGNING.md). The example source bundle ID is `org.libertyequalitydata.personalbrowser`; change it for your distribution. Apple managed entitlements, including Default Browser, do not transfer with source code.

## Snapshot and license

The [MIT License](LICENSE) permits personal, open-source, and commercial derivatives. Future snapshots may be unrelated code drops with no shared ancestry, API, data migration, or compatibility continuity. There is no publication cadence or promise to release every commercial change. See [snapshot model](SNAPSHOT_MODEL.md) and [snapshot metadata](SNAPSHOT.json).

The source is provided without warranty, hosted service, support SLA, or release cadence. Derivatives must not imply endorsement by Prifina, Liberty. Equality. Data., Apple, or supported websites. Product names and commercial identity are not licensed by the MIT source grant.
