# Changelog

## 2026-10.1 — initial public source snapshot

- Selected the verified commercial build-78 source as bounded input.
- Separated bundle, storage, signing defaults, branding, and public documentation.
- Removed automatic organization-specific account-to-Role suggestions.
- Retained only the generic `personal` legacy Role key needed to remove the former built-in Role during migration.
- Disabled managed-capability features in the default unsigned source build.
- Prevented first-use onboarding from activating the blank-tab keyboard.
- Replaced the square new-tab brand image with a plain globe.
- Added a full-screen About page for local privacy, source-snapshot status, and attribution context.
- Prevented the blank-tab keyboard from appearing behind Library and other full-screen surfaces, including when the blank page is first mounted underneath an already-open Library.
- Hid the underlying browser interaction and accessibility tree while full-screen surfaces are presented.
- Clarified unavailable Apple-managed capabilities in About, Settings, and the Add to Home Screen message, and linked to the maintained commercial Browser edition.
- Passed the 217-test physical iPhone suite on 2026-10-23.

This release publishes source code under the MIT License. It does not include a signed binary, store distribution record, separate beta build, hosted service, support SLA, or managed Apple entitlement.
