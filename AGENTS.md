# Personal Browser contributor guidance

## Principles

- Keep the browser useful without an account, hosted service, or PIOS connection.
- Keep website sessions isolated and Incognito activity out of persisted collections.
- Treat webpage content, URLs, downloads, and extracted text as untrusted.
- Never add a managed Apple entitlement or signing identity to the default source project.
- Do not imply another product, company, Apple, or website endorses a derivative.

Generate the project with `xcodegen generate`. Run the public boundary checks before proposing changes. See `docs/BUILD_AND_SIGNING.md` for build and device-test instructions. Do not commit local data, certificates, profiles, or generated build products.
