# Architecture and local data boundaries

## Principles

- The app remains useful alone, with no Core, PIOS, hosted backend, or account.
- Website sessions are isolated; Incognito does not enter normal retention paths.
- Reading a page and retaining a copy are separate actions.
- External page content is untrusted.

SwiftUI owns the browser shell and WebKit renders pages. `BrowserStore` owns tabs and collections; `BrowserPersistence` writes a JSON snapshot under the app's `PersonalBrowser` Application Support directory. Downloads, resume data, tab previews, and Library copies use that namespace. The separate bundle ID gives the app its own container and UserDefaults domain. There is no read or migration path into the commercial app's data.

**Sessions and Roles.** The initial website session is Personal. People can create more sessions; each uses its own persistent WebKit website-data store. Roles are optional owner-created labels for organizing tabs and saved items, not website identities. Automatic account/email-to-Role inspection is absent.

**Incognito.** Private tabs use a nonpersistent website-data store. They are omitted from persisted restoration, normal history, downloads records, and local Insights. Device and website behavior should still be checked on a signed physical build.

**Reader and Library.** Reader extracts a safe simplified view from the current page. Adding to Library or exporting a Reader PDF is explicit. Source pages can change; extracted content is not a trusted instruction or a verified copy of a site.

**Local Insights.** Foreground normal-browsing attention and media playback records stay local, are bounded in retention, and can be cleared. They are not sent to a publisher or PIOS service.

**Optional future compatibility.** PIOS or Core integration is only future direction. This snapshot has no PIOS wire protocol, App Group, account, or governed durable-save receipt. Sharing is the ordinary outward path.
