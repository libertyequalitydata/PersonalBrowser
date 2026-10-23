# Privacy

## Principles

- Ordinary browsing data stays on the device in this source build.
- Incognito does not enter normal history, saved tabs, or local Insights.
- Sharing, downloading, Reader capture, and transcription require user action.

Personal Browser has no app account, analytics service, telemetry endpoint, or PIOS connection. Websites opened in WebKit receive normal browser traffic and may use cookies, tracking, or their own accounts. Separate website sessions use separate persistent WebKit data stores; Incognito uses a nonpersistent store. UserDefaults holds local settings. Application Support stores browser state, previews, download resume data, and Library copies under `PersonalBrowser`; downloads are saved in Files-visible Documents/Downloads. Other apps or people with access to device Files can see exported/downloaded files. Local Insights measure normal foreground activity only and can be cleared in the app. The app does not upload these records to its publisher.

The privacy manifest declares UserDefaults use. Review it when adding APIs or data collection. This document describes this snapshot's source defaults; distributors must publish privacy terms for their own changes and distribution.
