# Contributing

## Principles

- Keep contributions local-first, privacy-preserving, and independently testable.
- Keep commercial identities, credentials, device records, and private data out of changes.
- Document behavior and rationale when changing product boundaries.

Read `AGENTS.md` and the [maintainer guide](docs/MAINTAINER_GUIDE.md) before starting. Open an issue before large scope changes. Generate the Xcode project from `project.yml`; do not commit it. Run `python3 scripts/verify_public_snapshot.py` and an unsigned generic iPhone build. Add proportional tests, describe any physical-device testing actually performed, and never reuse an older snapshot's test result as current evidence.

Pull requests should explain user-visible behavior, privacy/security impact, persisted-data compatibility, Incognito impact, tests run, and documentation changes. Contributions are submitted under the repository MIT License. Contributors retain attribution where applicable. See the [Code of Conduct](CODE_OF_CONDUCT.md).
