# Optional Default Browser capability

## Principles

- Apple's managed entitlement is granted to a specific app/team and never transfers with source.
- The default source build must work without it.
- Capability claims require a separately signed device build and verification.

This repository contains no `com.apple.developer.web-browser` entitlement. HTTP and HTTPS URL types in the source do not themselves make the app an approved Default Browser. A distributor seeking that capability must use a unique bundle ID, their own Apple Developer team, and Apple's current eligibility and approval process. After approval, configure the entitlement only in their private distribution project, review Apple's applicable requirements, sign, and verify system routing on a physical device. `BrowserAddToHomeScreenEnabled` and `BrowserPasskeyAuthorizationEnabled` are false in the default Info.plist; turn on only the feature whose entitlement and device behavior have been independently validated. Browser passkey authorization also requires the applicable iOS version and its own testing. Do not publish claims of approval from this snapshot.
