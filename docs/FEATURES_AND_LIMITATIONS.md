# Features and current limitations

This document describes snapshot `2026-10.1`. It is a boundary statement, not a roadmap promise.

## Browsing and navigation

- Normal tabs, pinned tabs, temporary overlay Subtabs, bookmarks, history, downloads, and address/search entry.
- Per-site choices for supported external-link behavior and installed-app handoff prompts.
- Per-tab minimized browser controls with a route back to pinned tabs and the main menu.
- New blank tabs are not retained as meaningful tabs until navigation occurs.

Site-specific rules and interface adaptations depend on website markup and navigation behavior. They can stop working when a website changes and should always leave a path back to ordinary browsing.

## Sessions, Roles, and privacy modes

- Separate persistent website sessions use separate WebKit data stores.
- Roles are optional labels for one person's context. They do not create separate people or automatically change website accounts.
- Incognito uses nonpersistent WebKit storage and is excluded from normal tab restoration, history, and local Insights.
- Deliberate outputs such as a downloaded or exported file can remain after an Incognito session.

## Saved content and reading

- Saved bookmarks retain a live destination and can include organization metadata.
- Reader attempts to extract the principal article content and image into a simplified local presentation.
- Library retains explicitly selected Reader captures and supported downloaded items.
- Reader PDF export creates a simplified document for explicit sharing or saving.

Reader extraction is best effort. Paywalls, scripts, unusual markup, dynamic feeds, and anti-automation controls can prevent a complete capture. A retained source URL is not a guarantee that the source remains available.

## Files and media

- Downloads include local metadata, grouping, retry/resume support where the server permits it, and Files-visible storage.
- Supported audio and video can use the app's player, speed controls, and explicit transcription action.
- PDF and supported documents have in-app viewing paths.

Playback, background audio, Picture in Picture, transcription, resume behavior, and format support still depend on iOS, device capability, codecs, and the downloaded file.

## Local Insights

Normal foreground browsing and media activity can be summarized locally by site and time period. Incognito is excluded. Insights are intended to demonstrate information the owner can use; this snapshot does not send the collection to a publisher, personal-data server, agent, or analytics service.

## Deliberately absent from the default source build

- No managed Default Browser entitlement.
- No browser passkey authorization capability.
- No custom Add to Home Screen capability.
- No App Group, cloud sync, account, hosted backend, PIOS connection, or Core connection.
- No general advertising blocker or promise to suppress every website prompt.
- No automatic AI analysis, personal-agent access, or background data export.
- No App Store or beta distribution record supplied by this repository.
- No migration from another browser installation or guarantee between future source snapshots.

Builders may implement these features in a derivative when they have the necessary authority, privacy design, platform capabilities, and verification. Their presence in another product does not transfer permission or entitlement to this source package.

The app's About page and capability-specific status messages explain these boundaries at the point of use. They also link to Apple's browser requirements and to the maintained commercial Browser edition for people who want to test the end-user product rather than build this source snapshot.
