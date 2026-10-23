# Build, signing, and physical-device verification

## Principles

- The repository builds unsigned by default and contains no team, profile, or managed entitlement.
- A distributor chooses a unique bundle ID and uses their own Apple Developer team.
- Device tests are reported only after actually running on a physical iPhone.

## Unsigned build

Install Xcode 26.3 or later and XcodeGen, then run. Snapshot `2026-10.1` was verified with Xcode 26.6:

```sh
xcodegen generate
xcodebuild -project PersonalBrowser.xcodeproj -scheme PersonalBrowser \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing
python3 scripts/verify_public_snapshot.py
```

`project.yml` is authoritative; the generated `.xcodeproj` is ignored. The example app ID is `org.libertyequalitydata.personalbrowser`, and the test ID is `.tests`. Change both for your distribution. Keep the identifiers separate from any commercial browser installation. Changing the bundle ID also creates a fresh app sandbox; this snapshot has no import or migration from another app.

## Signing for your own device

In a private working copy, edit the app and test bundle IDs in `project.yml` and run `xcodegen generate`. Do not edit only the generated Xcode project: regeneration discards those changes. For a connected iPhone, select the `PersonalBrowser` scheme and configure your own team for both targets. Override the source-only setting `CODE_SIGNING_ALLOWED=NO` to `YES` for this private build, either in a private project specification or on the `xcodebuild` command line with `CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=<your-team-id> CODE_SIGN_STYLE=Automatic`. Use the physical device as the test destination for the `PersonalBrowser` scheme; its test target is `PersonalBrowserTests`. Do not commit local signing changes or profiles. Install alongside any commercial app, launch, and record the actual test result and iOS/device model without publishing device identifiers or personal data.

## Primary Mac handoff checklist

1. Copy this sanitized source project alone to the Primary Mac; keep staging evidence and the commercial baseline private.
2. Regenerate from `project.yml`, choose independent signing and bundle IDs, and verify the installed display name and icon.
3. Run the complete test bundle on the physical iPhone. Record pass/fail counts and investigate failures.
4. Check that commercial browser data and settings remain unchanged. Verify a fresh Personal session, owner-created sessions, separate website cookies, and Incognito non-restoration.
5. Exercise browsing, tabs, Roles, bookmarks, history, downloads, Reader/PDF, Library, local Insights, site settings, and audio/transcription as applicable.
6. Confirm Add to Home Screen and browser passkey authorization remain unavailable in the default build. Do not request or assume Default Browser status.
7. Redact device names, UDIDs, URLs, account details, and logs before moving evidence into a public repository.

An unsigned generic build proves compilation only. It does not execute the iOS test bundle or establish device behavior.
