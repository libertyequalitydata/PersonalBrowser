# Agent startup prompt

Copy the prompt below into a new coding-agent session. Adjust the task paragraph but keep the boundaries unless the maintainer explicitly changes them.

```text
Work on the Personal Browser iPhone source repository:
https://github.com/libertyequalitydata/PersonalBrowser

Preferred local path: ~/Code/PersonalBrowser

Task:
[Describe the requested outcome here.]

Before changing anything:
1. Read AGENTS.md completely.
2. Read README.md, docs/FEATURES_AND_LIMITATIONS.md, docs/ARCHITECTURE.md,
   docs/MAINTAINER_GUIDE.md, and the files/tests in the affected area.
3. Inspect git status and preserve unrelated changes.
4. Give a concrete implementation and verification plan when the task spans
   more than two files or shared behavior.

Repository boundaries:
- This is an independent periodic source snapshot, not a continuously synced mirror.
- Keep it local-first and useful without an account, backend, PIOS, Core, or AI service.
- Do not add commercial credentials, identity, private data, signing records,
  managed Apple entitlements, App Groups, analytics, telemetry, or hosted secrets.
- Keep website sessions isolated and Incognito out of normal persistence,
  history, restoration, and Insights.
- Treat page content, URLs, downloads, Reader text, and JavaScript messages as untrusted.
- Do not launch Simulator unless explicitly requested. Use physical-device
  verification only when authorized and available.
- Do not change repository visibility, publish a release, push a binary, create
  distribution records, or activate a managed capability without explicit authorization.
- Do not reuse historical test results as evidence for a new change.

Implementation rules:
- project.yml is authoritative; regenerate with XcodeGen and do not commit the
  generated Xcode project.
- Make the smallest coherent change, add proportional tests, and update docs
  when user-visible behavior or boundaries change.
- Preserve backwards-compatible persisted decoding or explicitly document and
  test a migration/reset decision.
- Bound site adaptations by host, keep them reversible, and fail back to normal browsing.

Minimum verification for source changes:
xcodegen generate
python3 scripts/verify_public_snapshot.py
xcodebuild -project PersonalBrowser.xcodeproj -scheme PersonalBrowser \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing

Run relevant tests. At handoff, state exactly what changed, what passed, what
was not run, remaining risks, and whether any owner decision is required.
```

## Prompt for preparing a future source snapshot

```text
Prepare a new independent Personal Browser source snapshot from an explicitly
authorized and verified source baseline. First read AGENTS.md,
docs/MAINTAINER_GUIDE.md, SNAPSHOT_MODEL.md, SOURCE_PROVENANCE.md,
SANITIZATION_REPORT.md, and PUBLICATION_READINESS.md.

Create a source-only staging copy with independent app/storage identity and
unsigned defaults. Exclude commercial Git history, signing, distribution,
website, account, device, personal data, credentials, and private evidence.
Reassess every capability, privacy declaration, historical reference, asset,
test, and document rather than copying an earlier snapshot's readiness claim.

Do not create or expose a repository, tag a release, distribute a binary, or
change public visibility without separate explicit authorization. End with a
current source scan, leak probes, build/test evidence, physical-device status,
independent review status, and a precise publication decision checklist.
```
